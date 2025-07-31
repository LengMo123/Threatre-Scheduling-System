import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Savepoint;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import java.io.IOException;
import java.lang.reflect.Array;
import java.nio.IntBuffer;
import java.util.Properties;

import java.time.LocalDateTime;
import java.sql.Timestamp;
import java.util.Vector;

public class GigSystem {

    public static void main(String[] args) {

        // You should only need to fetch the connection details once
        // You might need to change this to either getSocketConnection() or getPortConnection() - see below
        Connection conn = getSocketConnection();

        boolean repeatMenu = true;
        
        while(repeatMenu){
            System.out.println("_________________________");
            System.out.println("________GigSystem________");
            System.out.println("_________________________");
            System.out.println("1: Find the line-up for a given gigID.");
            System.out.println("2: Organising a gig.");
            System.out.println("3: Booking a ticket.");
            System.out.println("4: Cancelling an act.");
            System.out.println("5: Tickets Needed To Sell");
            System.out.println("6: How many tickets sold.");
            System.out.println("7: Regular Customers.");
            System.out.println("8: Economically feasible gigs");
            
            System.out.println("q: Quit");

            String menuChoice = readEntry("Please choose an option: ");

            if(menuChoice.length() == 0){
                //Nothing was typed (user just pressed enter) so start the loop again
                continue;
            }
            char option = menuChoice.charAt(0);

            /**
             * If you are going to implement a menu, you must read input before you call the actual methods
             * Do not read input from any of the actual option methods
             */
            switch(option){
                case '1':
                    break;
                case '2':
                    break;
                case '3':
                    break;
                case '4':
                    break;
                case '5':
                    break;
                case '6':
                    break;
                case '7':
                    break;
                case '8':
                    break;
                case 'q':
                    repeatMenu = false;
                    break;
                default: 
                    System.out.println("Invalid option");
            }
        }
    }

    /*
     * You should not change the names, input parameters or return types of any of the predefined methods in GigSystem.java
     * You may add extra methods if you wish (and you may overload the existing methods - as long as the original version is implemented)
     */
    
     /** Select the actname, start time and finish time of the gig we want 
     * @param conn An open datebase connection
     * @param gigID The gigid of the gig from which we want to get the line-up 
    */
    public static String[][] option1(Connection conn, int gigID){ 
        String selectQuery = "SELECT actname,ontime::time, (ontime::time + INTERVAL '1 minute' * duration) FROM (act_gig JOIN Act USING(actid)) WHERE gigID = ? ORDER BY ontime::time"; // Select the ActName, OnTime and Offtime of the acts //
        String[][] lineup;   
        try{
            PreparedStatement preparedStatement = conn.prepareStatement(selectQuery); 
            preparedStatement.setInt(1, gigID);
            ResultSet lineups = preparedStatement.executeQuery();
            lineup = convertResultToStrings(lineups);   
            /* use the pre-defined convertResultToStrings() method to convert the query result set of gig line-up to 2D string array*/
            
            return lineup;
        
        }catch(SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
            return null;
        }
        
    }

     /** Organising a new gig 
     * @param conn An open datebase connection
     * @param venue The venue in which we want to organise the gig
     * @param gigTitle The gigtitle of the new organised gig.
     * @param actIDs The array of actIDs we want to organise in the gig
     * @param fees The act costs particularly for this gig
     * @param onTimes The start time of these acts
     * @param durations The duration time of these acts
     * @param adultTicketPrice The standard adult ticket price of this gig
    */
    public static void option2(Connection conn, String venue, String gigTitle, int[] actIDs, int[] fees, LocalDateTime[] onTimes, int[] durations, int adultTicketPrice){
        String gig_insertStatement = "INSERT INTO gig VALUES (DEFAULT, (SELECT venueid FROM venue WHERE venuename = ?),?,?,'GoingAhead')"; 
        String act_gig_insertStatement = "INSERT INTO act_gig VALUES (?,(SELECT gigID FROM gig WHERE gigtitle = ?),?,?,?)";
        String gig_ticket_insertStatement = "INSERT INTO gig_ticket VALUES ((SELECT gigID FROM gig WHERE gigtitle = ?), 'A', ?)";
        
        try{
            conn.setAutoCommit(false);
            /* Set autocommit to false so that we will not automatically commit these INSERT statements */
            PreparedStatement statement1 = conn.prepareStatement(gig_insertStatement);
            PreparedStatement statement2 = conn.prepareStatement(act_gig_insertStatement);
            PreparedStatement statement3 = conn.prepareStatement(gig_ticket_insertStatement);
            
            Savepoint s1 = null;
            s1 = conn.setSavepoint();
            /* Set a savepoint before we execute the INSERT statament, if there are invalid inputs, we rollback to this savepoint then commit 
             * So that the database will be in its initial state.
             */
            
            statement1.setString(1, venue);
            statement1.setString(2, gigTitle);
            statement1.setTimestamp(3,Timestamp.valueOf(onTimes[0]));
            try {
                int numGigInserted = statement1.executeUpdate();
                System.out.printf("%d gig is inserted, Should be 1\n", numGigInserted);
                statement3.setString(1, gigTitle);
                statement3.setInt(2, adultTicketPrice);
                int numTicketInserted = statement3.executeUpdate();
                System.out.printf("%d ticket is inserted, Should be 1\n", numTicketInserted);

                for (int i=0;i<actIDs.length;i++) {
                    statement2.setInt(1, actIDs[i]);
                    statement2.setString(2, gigTitle);
                    statement2.setInt(3, fees[i]);
                    statement2.setTimestamp(4, Timestamp.valueOf(onTimes[i]));
                    statement2.setInt(5, durations[i]);
                    statement2.addBatch();
                }

                int[] updateCounts = statement2.executeBatch();
                int totalacts = 0;
                for(int i = 0; i < updateCounts.length; i++){
                    totalacts += updateCounts[i];
                }
                System.out.println("Committed " + totalacts + " acts, Should be " + actIDs.length);
                if (numGigInserted < 1 || numTicketInserted < 1 || totalacts < actIDs.length) { 
                    /* Check how many gig, ticket and acts are inserted, if the number of inserted ones is less than input number, we know some input is invalid*/
                    System.out.println("Invalid input, we roll back the database to the state before the execution of Option 2");
                    conn.rollback(s1);
                    conn.commit();
                }
            } catch(SQLException e) {
                conn.rollback(s1);
                conn.commit();
            }
            conn.commit(); 
            /* If all the data input are valid, we won't rollback to savepoint s1, we will commit these data normally */
            conn.setAutoCommit(true);    
        }catch (SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
        }
    }

    /** Buying a ticket
     * @param conn An open datebase connection
     * @param gigid The gig we want to bug a ticket for
     * @param name The name of customer
     * @param email The email address of customer
     * @param ticketType The ticket type we wish to buy
     */
    public static void option3(Connection conn, int gigid, String name, String email, String ticketType){
        String ticket_insertStatement = "INSERT INTO ticket VALUES(DEFAULT,?,?,(SELECT price FROM gig_ticket WHERE gigID = ? and pricetype=?),?,?)";
        Savepoint s1 = null;
        
        try{
            PreparedStatement statement1 = conn.prepareStatement(ticket_insertStatement);
            conn.setAutoCommit(false);
            s1 = conn.setSavepoint();
            statement1.setInt(1,gigid);
            statement1.setString(2, ticketType);
            statement1.setInt(3,gigid);
            statement1.setString(4,ticketType);
            statement1.setString(5,name);
            statement1.setString(6,email);
            int numTicketBought;
            try {
                numTicketBought = statement1.executeUpdate();
                if (numTicketBought < 1) {  /* If the ticket type doesn't exist or the gigid we wish to buy a ticket for doesn't exist, etc. Rollback to the initial state */
                    conn.rollback(s1);
                    conn.commit();
                }
            } catch (SQLException e) {
                conn.rollback();
                conn.commit();
            }
            conn.commit();
            /* If all the data input are valid, we won't rollback to savepoint s1, we will commit these data normally */
            conn.setAutoCommit(true);
        } catch (SQLException e){
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
        }
    }

    /** Cancel an act
     * @param conn An open datebase connection
     * @param gigid The gig we want to delete an act from
     * @param actName The actname of the act we wish to delete
     */
    public static String[] option4(Connection conn, int gigID, String actName){
        String act_gig_updateStatement = "DELETE FROM act_gig WHERE gigID = ? AND actID = (SELECT actID FROM Act WHERE actName = ?)";
        String gigstatus_selectStatement = "SELECT gigstatus FROM gig WHERE gigID = ?";
        String emailAddress_statement = "SELECT DISTINCT CustomerEmail FROM ticket WHERE gigID = ? AND Cost = 0 ORDER BY CustomerEmail";
        int totalDeletedrows = 0;
        String[][] gig_status; 
        String[][] customer_email;
        String[] outputEmails;
        try {
            PreparedStatement statement1 = conn.prepareStatement(act_gig_updateStatement);
            conn.setAutoCommit(false);
            statement1.setInt(1, gigID);
            statement1.setString(2, actName);
            
            int executecount = statement1.executeUpdate();
            for (int i = 0; i < executecount; i++) {
                totalDeletedrows += 1;
            }
            System.out.println("Deleted " + totalDeletedrows + " acts");
            conn.commit();
            conn.setAutoCommit(true);
            PreparedStatement statement2 = conn.prepareStatement(gigstatus_selectStatement); /* After the deletion of the act, we need to know if the gig is cancelled */
            statement2.setInt(1,gigID);
            ResultSet result1 = statement2.executeQuery();
            gig_status = convertResultToStrings(result1);
            System.out.printf("The gig %d is %s.\n",gigID,gig_status[0][0]);
            if (gig_status[0][0].equals("Cancelled")) {                                    /* If the gig is cancelled, we need to get the affected email addresses of the customers and return them as a 2D array*/
                PreparedStatement statement3 = conn.prepareStatement(emailAddress_statement);
                statement3.setInt(1,gigID);
                ResultSet result2 = statement3.executeQuery();
                customer_email = convertResultToStrings(result2);
                outputEmails = new String[customer_email.length];
                System.out.println("The customers that have been affected have email addresses:");
                printTable(customer_email);
                for (int i = 0; i < customer_email.length; i++) {
                    outputEmails[i] = customer_email[i][0];
                }
                return outputEmails;
            }
            else {
                System.out.println("The gig is still GoingAhead");                         /* If the gig is still GoingAhead, we return NULL */
                return null;
            }
        }catch (SQLException e){
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
            return null;
        }
        
    }
    /** Get the tickets needed to sell to be able to pay the actfees and the venue hirecost
     *  @param conn An open datebase connection
     */
    public static String[][] option5(Connection conn){
        String gig_selectStatement = "SELECT gigID, ticketsToSell(allGig.gigID) FROM gig AS allGig";
        String[][] gig_ticketsNeededToSell;

        try {
            PreparedStatement statement1 = conn.prepareStatement(gig_selectStatement);
            ResultSet lineups = statement1.executeQuery();
            gig_ticketsNeededToSell = convertResultToStrings(lineups);


        } catch (SQLException e){
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();

            return null;
        }
        return gig_ticketsNeededToSell; 
    }
    /** Get the number of tickets every act sold as the headline act of a gig in every year
     *  @param conn An open datebase connection
     */
    public static String[][] option6(Connection conn){
        String act_tickets_Sold_String = "SELECT * FROM op6_result_view";
        String[][] output;
        try {
            PreparedStatement statement1 = conn.prepareStatement(act_tickets_Sold_String);
            ResultSet result = statement1.executeQuery();
            output = convertResultToStrings(result);
        } catch (SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();

            return null;
        }
        
        return output;
    }
    /** Get the regular customers for every act
     *  @param conn An open datebase connection
     */
    public static String[][] option7(Connection conn){
        String regularCustomer_String = "SELECT * FROM op7_result_view";
        String[][] output;
        try {
            PreparedStatement statement1 = conn.prepareStatement(regularCustomer_String);
            ResultSet result = statement1.executeQuery();
            output = convertResultToStrings(result);
            printTable(output);
        } catch (SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();

            return null;
        }
        return output;
    }
    /** Get the economically feasible gigs as a combination of venue and act and the tickets needed to sell to be able to pay for the total fees
     *  @param conn An open datebase connection
     */
    public static String[][] option8(Connection conn){
        String economically_feasible_gigs = "SELECT * FROM op8_result_view";
        String[][] output;
        try {
            PreparedStatement statement1 = conn.prepareStatement(economically_feasible_gigs);
            ResultSet result = statement1.executeQuery();
            output = convertResultToStrings(result);
            printTable(output);
        } catch (SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();

            return null;
        }
        return output;
    }

    /**
     * Prompts the user for input
     * @param prompt Prompt for user input
     * @return the text the user typed
     */

    private static String readEntry(String prompt) {
        
        try {
            StringBuffer buffer = new StringBuffer();
            System.out.print(prompt);
            System.out.flush();
            int c = System.in.read();
            while(c != '\n' && c != -1) {
                buffer.append((char)c);
                c = System.in.read();
            }
            return buffer.toString().trim();
        } catch (IOException e) {
            return "";
        }

    }

    /**
    * Gets the connection to the database using the Postgres driver, connecting via unix sockets
    * @return A JDBC Connection object
    */
    public static Connection getSocketConnection(){
        Properties props = new Properties();
        props.setProperty("socketFactory", "org.newsclub.net.unix.AFUNIXSocketFactory$FactoryArg");
        props.setProperty("socketFactoryArg",System.getenv("HOME") + "/cs258-postgres/postgres/tmp/.s.PGSQL.5432");
        Connection conn;
        try{
          conn = DriverManager.getConnection("jdbc:postgresql://localhost/cwk", props);
          return conn;
        }catch(Exception e){
            e.printStackTrace();
        }
        return null;
    }

    /**
     * Gets the connection to the database using the Postgres driver, connecting via TCP/IP port
     * @return A JDBC Connection object
     */
    public static Connection getPortConnection() {
        
        String user = "postgres";
        String passwrd = "password";
        Connection conn;

        try {
            Class.forName("org.postgresql.Driver");
        } catch (ClassNotFoundException x) {
            System.out.println("Driver could not be loaded");
        }

        try {
            conn = DriverManager.getConnection("jdbc:postgresql://127.0.0.1:5432/cwk?user="+ user +"&password=" + passwrd);
            return conn;
        } catch(SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
            System.out.println("Error retrieving connection");
            return null;
        }
    }

    public static String[][] convertResultToStrings(ResultSet rs){
        Vector<String[]> output = null;
        String[][] out = null;
        try {
            int columns = rs.getMetaData().getColumnCount();
            output = new Vector<String[]>();
            int rows = 0;
            while(rs.next()){
                String[] thisRow = new String[columns];
                for(int i = 0; i < columns; i++){
                    thisRow[i] = rs.getString(i+1);
                }
                output.add(thisRow);
                rows++;
            }
            // System.out.println(rows + " rows and " + columns + " columns");
            out = new String[rows][columns];
            for(int i = 0; i < rows; i++){
                out[i] = output.get(i);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return out;
    }

    public static void printTable(String[][] out){
        int numCols = out[0].length;
        int w = 20;
        int widths[] = new int[numCols];
        for(int i = 0; i < numCols; i++){
            widths[i] = w;
        }
        printTable(out,widths);
    }

    public static void printTable(String[][] out, int[] widths){
        for(int i = 0; i < out.length; i++){
            for(int j = 0; j < out[i].length; j++){
                System.out.format("%"+widths[j]+"s",out[i][j]);
                if(j < out[i].length - 1){
                    System.out.print(",");
                }
            }
            System.out.println();
        }
    }
    private static boolean checkValues(String provided, String expected) throws TestFailedException{
        if(!provided.equals(expected)){
            throw new TestFailedException(provided, expected);
        }
        return true;
    }
}
