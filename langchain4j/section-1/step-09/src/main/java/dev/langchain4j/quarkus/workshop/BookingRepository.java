package dev.langchain4j.quarkus.workshop;

import dev.langchain4j.agent.tool.Tool;
import io.quarkus.hibernate.orm.panache.PanacheRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;

import java.time.LocalDate;
import java.util.List;

import static dev.langchain4j.quarkus.workshop.Exceptions.BookingCannotBeCancelledException;
import static dev.langchain4j.quarkus.workshop.Exceptions.BookingCannotBeCreatedException;
import static dev.langchain4j.quarkus.workshop.Exceptions.BookingNotFoundException;
import static dev.langchain4j.quarkus.workshop.Exceptions.CustomerNotFoundException;

@ApplicationScoped
public class BookingRepository implements PanacheRepository<Booking> {


    @Tool("""
          Create a new car rental booking for a customer. \
          Dates must be ISO dates, for example 2026-11-20. \
          The location is the city where the car is picked up.\
          """)
    @Transactional
    public Booking createBooking(String customerFirstName, String customerLastName,
                                 LocalDate dateFrom, LocalDate dateTo, String location) {
        var found = Customer.find("LOWER(firstName) = LOWER(?1) and LOWER(lastName) = LOWER(?2)",
                                  customerFirstName, customerLastName).singleResultOptional();
        if (found.isEmpty()) {
            throw new CustomerNotFoundException(customerFirstName, customerLastName);
        }
        var customer = (Customer) found.get();

        // These arguments were chosen by the model, not by your application, so
        // they are untrusted input. Validate them exactly as you would validate a
        // request body: the model is perfectly capable of inventing a booking that
        // starts in the past.
        if (dateFrom == null || dateTo == null) {
            throw new BookingCannotBeCreatedException("both dates are required");
        }
        if (dateFrom.isBefore(LocalDate.now())) {
            throw new BookingCannotBeCreatedException("the start date is in the past");
        }
        if (!dateTo.isAfter(dateFrom)) {
            throw new BookingCannotBeCreatedException("the end date must be after the start date");
        }
        if (location == null || location.isBlank()) {
            throw new BookingCannotBeCreatedException("a pick-up location is required");
        }

        var booking = new Booking();
        booking.customer = customer;
        booking.dateFrom = dateFrom;
        booking.dateTo = dateTo;
        booking.location = location;
        persist(booking);
        return booking;
    }

    @Tool("Cancel a booking")
    @Transactional
    public void cancelBooking(long bookingId, String customerFirstName, String customerLastName) {
        Booking booking = getBookingDetails(bookingId, customerFirstName, customerLastName);
        // too late to cancel
        if (booking.dateFrom.minusDays(11).isBefore(LocalDate.now())) {
            throw new BookingCannotBeCancelledException(bookingId);
        }
        // too short to cancel
        if (booking.dateTo.minusDays(4).isBefore(booking.dateFrom)) {
            throw new BookingCannotBeCancelledException(bookingId);
        }
        delete(booking);
    }

    @Tool("List booking for a customer")
    @Transactional
    public List<Booking> listBookingsForCustomer(String customerName, String customerSurname) {
        var found = Customer.find("LOWER(firstName) = LOWER(?1) and LOWER(lastName) = LOWER(?2)", customerName, customerSurname).singleResultOptional();
        if (found.isEmpty()) {
            throw new CustomerNotFoundException(customerName, customerSurname);
        }
        return list("customer", found.get());
    }


    @Tool("Get booking details")
    @Transactional
    public Booking getBookingDetails(long bookingId, String customerFirstName, String customerLastName) {
        Booking found = findById(bookingId);
        if (found == null) {
            throw new BookingNotFoundException(bookingId);
        }
        if (!found.customer.firstName.equals(customerFirstName) || !found.customer.lastName.equals(customerLastName)) {
            throw new BookingNotFoundException(bookingId);
        }
        return found;
    }
}
