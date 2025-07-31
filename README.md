# GigSystem
    A system to store information about which acts have played in a particular gig and in a particular venue

## Option 1: Get the gig line-up the gig we specify: Get the actname, act start time and finish time of the gig we input
1. We enter the gigid as input, selectQuery gets actids, *start times* and durations from act_gig JOIN act table using the actIDs in the gig we input. 
2. For the finish time, we get it by adding duration of act(in minutes) to the start time. 
3. For the actnames, we join the act and act_gig table on actIDs in the gig to get the corresponding actnames of the acts in the gig
4. Then we output actname, start time and finish time from the JOIN of Act and act_gig tables.

## Option 2: Organising a new gig
1. We enter the venuename, gigTitle, list of actIDs, list of actfees, list of onTimes(act start times), list of durations of acts, adultTicketPrice of the new gig.
2. gig_insertStatement will INSERT into gig table with the venueid of the venue the gig is gonna be held in, the gig title name and its start time, decided by the start time of the first act in the gig(onTimes[0]). We will get the venue id FROM venue table using the input venue name.
3. gig_ticket_insertStatement will INSERT into gig_ticket table with its ticketprice for the standard adult ticket of the gig.
4. act_gig_insertStatement will INSERT into act_gig table with the actIDs, their act fees and the corresponding start time and durations of the acts.
5. If some input data is invalid, where  
    `numGigInserted < 1 || numTicketInserted < 1 || totalacts < actIDs.length`
    Which means we inserted 0 gig or 0 ticket or less acts than the number of acts we input
    Then the input data must be breaking the rules of the gig system so that these data won't be actually inserted into the database. So that we must rollback the database to the state before all those insertion happened where we clarify a savepoint s1 for it before Step 2.
    The TRIGGER FUNCTIONs for detecting invalid data in option 2 are introduced in TRIGGER part.
    - For `numGigInserted < 1` : the gig must be either start at the same with another gig in the same venue or the gap from its previous gig or next gig in the same venue to itself is less than 3 hours as Gigs on the same day in the venues would need 3-hour gap for the staff to clean the venueThese will be checked by TRIGGER FUNCTION multiple_gigs_venue_sameTime().
    - For `numTicketInserted < 1` : Input adult ticket price is negative which will break the constraint on ticket price.
    - For `totalacts < actIDs.length`, some acts break the rules.
        1. They overlap with each other (In one gig, one act starts earlier than when the previous act finished OR two acts start at the same time). This could be checked by TRIGGER FUNCTION act_overlap()
        2. Some acts is performing at another gig at the same time and same date. This could be checked by TRIGGER FUNCTION act_in_multiple_gigs()
        3. Some acts are performing at another gig at the same date, not same time. By the assumption that it takes 20 minutes to get from one gig to another, there isn't 20 minutes gap between the acts. This could be checked by TRIGGER FUNCTION act_20mins_gap().
        4. Gigs on the same day in the venues would need 3-hour gap for the staff to clean up the venue, if in the *numGigInserted* case, the start time of the gig leaves 3-hour gap, but the finish time of acts in the gig might shorten the gap to less than 3 hours. This would make the whole gig invalid. This could be checked by TRIGGER FUNCTION new_act_3hourGap_gigs().

## Option 3: Booking a ticket: Book a ticket for a gig using the customer name, customer email and the price type of the ticket
1. ticket_insertStatement will INSERT into ticket table with customer's name and email, the gig we want to buy ticket for and its pricetype.
2. If `numTicketBought < 1`, the input data must be invalid.  
- The gig of the ticket does not exist. 
- The pricetype of the ticket for that gig does not exist.
- The customer is using a different name with his/her email when buying a ticket. TRIGGER FUNCTION customer_sameName_sameEmail() can detect invalid combination of customer name and email for this case.
- The customer email is not a valid email. TRIGGER FUNCTION customer_validEmail() can detect invalid email for this case.
So that we must rollback the database to the state before all those insertion happened where we clarify a savepoint s1 for it before Step 1 and commit so that the database will be in its initial state.
3. If `numTicketBought` is not smaller than 1, specifically equal to 1. Then we just commit the data, no need to rollback to savepoint s1.

## Option 4: Cancelling an act: Cancelling all the act performances of an act in the specified gig
1. We take the gigid of the gig we want to cancel acts in and the actname of the acts we want to cancel in the gig.
2. act_gig_updateStatement will delete all the acts with actname `actName` from the gig with gigid `gigID`. Since there are only actID of acts in act_gig table, we will get the corresponding actname by `SELECT actID FROM Act WHERE actName = ?` (? is replaced with our input by `statement.setString(2, actName)`).
3. After the deletion, if the deleted acts satisfy one of the following conditions
    - The deleted act is the headline act of the gig.
    - The deleted act will make the act before it and after it gap more than 20 minutes from each other. 
    TRIGGER FUNCTION delete_act_20MinsGap() can make sure that if these two cases happen, the gig will be cancelled and the cost of tickets sold for that gig in the ticket table will be changed to 0.
4. We can know if the gig is cancelled by `SELECT gigstatus FROM gig WHERE gigID = ?` to get gigstatus of the gig.
    - If the gig is cancelled `if (gig_status[0][0].equals("Cancelled"))` is TRUE, we will get the customer emails (no duplicates) in alphabetical order of the customers who bought the ticket for this gig by `SELECT DISTINCT CustomerEmail FROM ticket WHERE gigID = ? AND Cost = 0 ORDER BY CustomerEmail`. `DISTINCT` guarantees no duplicates and `Cost = ` due to the cost of tickets of that gig are all zero now. Output all these customer emails as an 2D array.
    - If the gig is not cancelled `if (gig_status[0][0].equals("Cancelled"))` is FALSE, we just tell the user the gig is still GoingAhead and output NULL.

## Option 5: Tickets Needed to Sell: Get the tickets we needed to sell for every gig that being able to pay all the agreed fees
1. gig_selectStatement `SELECT gigID, ticketsToSell(allGig.gigID) FROM gig AS allGig` will get all the gigid of gigs and their corresponding number of standard adult tickets still needed to sell to be able to pay the hirecost of the venue and all the act fees in that gig. This statement calls a function `ticketsToSell(gigID int)`(LINE 443 - 470 in schema.sql). 
    - This function will take the gigID as input.
        1. Get the total fees of all the acts in the gig.
        2. Get the hirecost of the venue the gig is held in.
        3. Get the number of tickets of that gig already sold.
        4. Get the total cost of the sold tickets.
        5. Get the price of standard adult ticket of the gig
        6. If there is no tickets sold for that gig, we divide the sum of total actfees and venue hirecost by the standard adult ticket price to get the number of tickets needed to sell. Note that we cast the standard adult ticket price to float so that in case there is a remainder when we do the division, we can get the smallest integer larger than the result of division to guarantee we can cover the total fees.
        7. If there are some tickets sold for that gig, we do the same version of division with one thing different that we will subtract the total cost of sold tickets from the total fees because the gig already cover part of fees with selling tickets. We just need the tickets STILL needed to sell.
        8. RETURN the tickets still needed to sell as output.
2. Output the result of gig_selectStatement.

## Option 6: How Many Tickets Sold:  The number of tickets that each act has sold each year and the number of tickets ever sold by each act when the act was a headline act
1. act_tickets_Sold_String `SELECT * FROM op6_result_view` get the number of tickets that each act has sold each year and the number of tickets ever sold by each act when the act was a headline act. *Headline Act* --The final or the only act in a gig.
2. op6_result_view contains several steps (LINE 490 - 508 in schema.sql)
    - op6_view1 (LINE 490 - 493) Get the number of tickets sold by each act as the headline act of a gig in each year. We use `Total` to denote the total number of tickets sold by each act.
    - op6_view2 (LINE 495 - 498) Get the number of tickets each customer bought for each act as the headline act of a gig in each year. In this VIEW, the year column is casted to text type because we will UNION op6_view1 and op6_view2 together, the column need to match the type of the `Total` text column in op6_view1.
    - op6_view3 (LINE 500 - 503) Get the total number of tickets sold by each act as the headline act of a gig. We use this view as the order tool to order the acts in the result in the order of the number of tickets sold by each act.
    - op6_result_view (LINE 505 - 508) UNION op6_view1 and op7_view2 to get the table including the total number of tickets, and join op6_view3 to order the table by total number of tickets sold by each act. UNION will combine the number of tickets sold each year and total number of tickets sold by each act together in one column.
3. Output the result of op6_result_view

## Option 7: Regular Customers: Get the name of customers who have attended at least one of these gigs per calendar year (if the act performed such a gig as a headline act in that year)
1. regularCustomer_String `SELECT * FROM op7_result_view` get all the acts which has ever performed as a headline act and their regular customers.
2. op7_result_view contains several steps (LINE 510 - 526 in schema.sql)
    - op7_view1 (LINE 510 - 514) Get the number of distinct years that each act performing as a headline act in a 'GoingAhead' gig. (The gigstatus must not be 'Cancelled').
    - op7_view2 (LINE 516 - 520) Get the number of distinct years that each customer bought ticket(s) for the act performing as a headline act.
    - op7_result_view (LINE 522 - 526) Get all the acts performed as a headline act in a 'GoingAhead' gig and their regular customers. The idea is to compare the number of distinct years that the act performing as a headline act in a 'GoingAhead' gig and the number of distinct years that the customer bought ticket(s) for the act performing as a headline act. If a customer is a regular customer for an act, then he must bought the tickets for all the year of the act as the headline act of a gig. So these two numbers must equal to each other, if not, the customer is not a regular customer. We use `LEFT JOIN` here because we want to keep the acts that performed as a headline act but no customer bought tickets for.
3. Output the result of op7_result_view.

## Option 8: Economically Feasible Gigs: Assume we try to organise new gigs, get all the gigs containing only one act and the number of tickets which its price doesn't exceed the average ticket price of tickets ever sold the gig would need to sell to be able to pay the venue hirecost and the fee of the only act. The number of tickets needed to sell can't exceed the venue capacity
1. economically_feasible_gigs `SELECT * FROM op8_result_view` get all the economically feasible gigs.
2. op8_result_view contains several steps (LINE 528 - 537 in schema.sql)
    - op8_view1 (LINE 528 - 531) We do CROSS JOIN to get every combination of the venue and the act, and then we calculate the sum of their hirecost and standardfee. Divide it by the average ticket price of sold tickets to get the ticket needed to sell to be able to pay the sum fee of venuecost and actfee.
    - op8_result_view (LINE 533 - 537) We JOIN op8_view1 with venue table to get the capacity of all venues, then we exclude the rows where the tickets needed to sell is bigger than the venue capacity to get the result table of Option 8 as we can't sell more tickets than the capacity of the venue.
3. Output the result of op8_result_view. 

# TRIGGERS (LINE 53 - 441 in schema.sql)
1. act_overlap() --check if existed acts overlap or start at the same time with new act in the same gig--
2. act_20mins_gap() --check if existed acts gap from the new act for too long in the same gig( 20 minutes)--
3. act_in_multiple_gigs() --check if there is a 20-minute gap between new act and existed acts with same actID--
4. multiple_gigs_venue_sameTime() --check if there is a gig using the same venue at the same time with new gig, if not at the same time, check if there is at least 3-hour gap between these gigs--
5. new_act_3hourGap_gigs() --This function is aiming at the same target as the previous one, but the previous one is checking if the gigdate is invalid, this one is checking if newly inserted act in a gig would be invalid based on the 3-hour gap rule--
6. act_NoEarlierThan_gigdate() --check if an act starts earlier than the gigdate of its gig--
7. firstAct_gig() --check if the first act in an gig starts earlier than the gigdate of its gig--
8. act_noLaterThan_11_59_pm() --Check if an act finishes later than 11:59 p.m.--
9. ticketsMoreThanCapacity() --Check if the gig sold more tickets more than the capacity of its venue
10. delete_act_20MinsGap() --Check if the deletion of an act would result in the cancellation of its gig--
11. customer_sameName_sameEmail() --Check if the customer always uses the same name and email--
12. customer_validEmail() --Check if the customer's email is in valid format--

# FUNCTIONS (LINE 443 - 488 in schema.sql)
1. ticketsToSell(gig_ID int)  --Get the tickets needed to sell to be at least able to pay the agreed fees of the specified gig--
2. headlineAct_ofGig(select_gig_ID int) --Get the headline act of the specified gig--

# Design Choices
1. Act:
    - {genre, standardfee, actname} functionally depend on {actID}, but {genre, standardfee} can also depend on {actname}.
    - This means there is transitive functional dependency in Act table. So this table is in 2NF. We are able to improve it to 3NF by getting rid of actID column and use {actName} as primary key as actname is also unique in the relation. 
    - But it might be better to keep actID because actID(which is a SERIAL type variable) is a good way to give a clear view of the acts by just looking at their id numbers instead of plenty of LONG act names (as actname is VARCHAR(100) type variable although we only see relatively short act names in our test data, there might be much much longer names in the future use). 
    - It is also more convenient when it comes to organise a new gig, we can enter actIDs as input instead of long non-trivial actNames which could lead to a typo very easily. The id column can also give us a view of the order of the acts being inserted into our system.
    - So the functionally dependency in Act table is fine.
2. act_gig:
    - {actfee, ontime, duration} functionally depend on {actid,gigid}. This relation is in 3NF
        1. There are no non-atomic columns. e.g. An act in a gig can't have two actfees
        2. No proper subset of the key determines a non-key attribute. e.g. The same acts in different gig might have different act fees.
        3. No transitive functional dependency. e.g. even with same actNames, the same acts in different gigs might have different act fees, start time and duration.
    - So the functionaly dependency in gig table is fine.as  Plus, if the gig is deleted, all the acts in this gig should be deleted from the table too. 
3. gig_ticket:
    - {pricetype, price} functionally depend on {gigid}. If the gig is deleted, all types of tickets for this gig should be deleted too. The same type of ticket in different gig might have different prices. Functionally dependency in gig_ticket table is fine.
4. venue table:
    - {hirecost, capacity, venuename} functionally depend on {venueid}, but {hirecost, capacity} can also depend on {venuename}. 
    - This means there is transitive functional dependency in venue table. So this table is in 2NF. We are able to improve it to 3NF by getting rid of venueID column and use {venueName} as primary key as venuename is also unique in the relation. 
    - But it might be better to keep venueID because venueID (which is a SERIAL type variable) is a good way to give a clear view of the venues by just looking at their id numbers instead of plenty of long venue names(as venuename is VARCHAR(100) type variable, although we only see relatively short venue names in our test data, there might be much much longer names in the future use). 
    - In this way, all the non-key attributes functionally are fully functionally dependent on the key. The id column can also give us a view of the order of the venues being inserted into our system.
    - So the functionally dependency in venue table is fine.
5. gig table:
    - {gigtitle,gigdate,gigstatus,venueid} functionally depend on {gigid}. It is in 3NF. Because 
        1. There are no non-atomic columns. e.g. An gig can't have several titles
        2. No proper subset of the key determines a non-key attribute. e.g. The same gigs in different gig might have different act fees.
        3. No transitive functional dependency. e.g. gigdate does not functionally depend on gigtitle as there might be two gigs on the same date having different gigtitle (As they could be in different venue on the same time).
        So the functionaly dependency in gig table is fine.
6. ticket table:
    - {CustomerName, CustomerEmail, Cost, pricetype, gigid} functionally depend on {ticketid}. But {CustomerName} functionally depend on {CustomerEmail} at the same time. This means non-key attributes functionally depend on other non-key attributes(Transitive functional dependency). 
    - We can create a new table customer to store the customer personal information with columns{customername, customeremail} so that if the gig is cancelled, we can still know the name and email of an customer. We keep customeremail column in ticket table because customeremail is unique and two customer might have different names while they must have different emails. 
    - Then customer table is in 3NF, {CustomerEmail} -> {Customername}
      New ticket table is in 3NF, {ticketid} -> {CustomerEmail, Cost, pricetype, gigid}.
        1. There are no non-atomic columns. e.g. An ticket can't have two cost values
        2. ticketid determines every other column in the table and there is no subkey. As ticketid is the only key.
        3. No transitive functional dependency. e.g. With with different gigid and pricetype, the cost buying that ticket might be the same.
7. Whole database
    - The database is in 1NF intuitively. There can't be two values in the same variable as the database is well-structured.
    - There is an intuitive functional dependency between tables in the database.
        - {gig} -> {gig_ticket}
    - Suppose gig table is the superkey of the table. There are other tables are independent of gig table. For example, two different gigs can be held in the same venue at different time. And two different tickets can be sold for the same gig.
    - So not all the tables in our database are functionally dependent on gig table. And at the same time, we can't find any suitable key intuitively. Then the whole database is not in 2NF form so that it is not in 3NF and BCNF as well.
    - But the whole database is fine overall after the addition of customer table although it is only in 1NF. Because the related tables can be joined using the superkey or subset of superkeys. For instance, {act_gig.actID} -> {Act.actID}, {gig_ticket.gigID} -> {gig.gigID}. So there will be no additive joins when we join the tables.
    - We will not have problems INSERTing data because there are primary keys in every table, which guarantees no duplicate rows. The related tables can be joined using the superkey or subset of superkeys. For instance, {act_gig.actID} -> {Act.actID}, {gig_ticket.gigID} -> {gig.gigID}. For example, if we are trying to insert an act for an not-existing gig or buy an ticket for an not-existing gig, we will receive SQL error preventing us from it.
    - We will not have problems UPDATEing data, because all the mattering data is ON UPDATE CASCADE. If we update gigID of a gig, the database changes gigid in act_gig table as well. For unmattering data, if we change the standard ticket price of a gig, it would not violate any constraints as both gig and ticket tables related to gig_ticket table don't depend on price of the ticket of a gig. But in general knowledge way, this could possibly lead to some confusions because if we change all the ticket prices of a gig to zero, then the gig cannot make any money as all tickets are free. This might be unreasonable in common knowledge
    - We might have problems DELETEing data, suppose we deleted all the ticket types of a gig, then the gig should be made invalid or cancelled because customer couldn't buy any ticket from the gig. But we have no special rule for this case as gig table doesn't depend on gig_ticket table. (Even this case could only happen if we try to manually delete data from our database). But for people who have direct access to our system, this could be a potential problem.
