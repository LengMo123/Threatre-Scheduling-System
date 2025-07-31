/*Put your CREATE TABLE statements (and any other schema related definitions) here*/
DROP TABLE IF EXISTS Act CASCADE;
DROP TABLE IF EXISTS act_gig CASCADE;
DROP TABLE IF EXISTS gig_ticket CASCADE;
DROP TABLE IF EXISTS gig CASCADE;
DROP TABLE IF EXISTS venue CASCADE;
DROP TABLE IF EXISTS ticket CASCADE;
CREATE TABLE Act (
    actID SERIAL PRIMARY KEY, --actID should be the primary key--
    actname VARCHAR(100) UNIQUE, --actname is unique--
    genre VARCHAR(10),
    standardfee INTEGER CHECK(standardfee >= 0) --standardfee is non-negative--
);
CREATE TABLE venue (
    venueid SERIAL PRIMARY KEY, --venueid should be the primary key since it is SERIAL--
    venuename VARCHAR(100) UNIQUE, --venuename is unique--
    hirecost INTEGER CHECK(hirecost >= 0), --hirecost is non-negative--
    capacity INTEGER
);

CREATE TABLE gig (
    gigID SERIAL PRIMARY KEY, --gigid should be the primary key as it is SERIAL --
    venueid INTEGER REFERENCES venue(venueid) ON DELETE CASCADE ON UPDATE CASCADE, --if the referencing venueid in venue table is deleted/updated, the gig row using that venue is deleted/updated--
    gigtitle VARCHAR(100),
    gigdate TIMESTAMP,  
    gigstatus VARCHAR(10) 
);

CREATE TABLE gig_ticket (
    gigID INTEGER REFERENCES gig(gigID) ON DELETE CASCADE ON UPDATE CASCADE, --if the referencing gigid in gig table is deleted/updated, the ticket of that gig is deleted/updated--
    pricetype VARCHAR(2),
    price INTEGER CHECK(price >= 0), --ticket price is non-negative-- 
    UNIQUE(gigID, pricetype) -- Assume that every ticket shouldn't have same type of tickets at different price
);

CREATE TABLE act_gig (
    actID INTEGER REFERENCES Act(actID) ON DELETE CASCADE ON UPDATE CASCADE, --if the referencing actid in Act table is deleted/updated, all the acts of that actid is deleted/updated--
    gigID INTEGER REFERENCES gig(gigID) ON DELETE CASCADE ON UPDATE CASCADE, --if the referencing gigid in gig table is deleted/updated, the act rows of that gig is deleted/updated--
    actfee INTEGER CHECK(actfee >= 0),  --actfee is non-negative--
    ontime TIMESTAMP,
    duration INTEGER 
);

CREATE TABLE ticket (
    ticketid SERIAL PRIMARY KEY,
    gigID INTEGER REFERENCES gig(gigID) ON DELETE CASCADE ON UPDATE CASCADE, --if the referencing gigid in gig table is deleted/updated, the sold ticket row of that gig is deleted/updated--
    pricetype VARCHAR(2),
    Cost INTEGER,
    CustomerName VARCHAR(100),
    CustomerEmail VARCHAR(100),
    FOREIGN KEY(gigID, pricetype)
    REFERENCES gig_ticket(gigID,pricetype)
);

CREATE OR REPLACE FUNCTION act_overlap() --check if existed acts overlap or start at the same time with new act in the same gig--
RETURNS TRIGGER
language plpgsql
AS $$
    DECLARE 
        act_time TIMESTAMP;
    BEGIN
        SELECT ontime INTO act_time FROM act_gig WHERE gigid = NEW.gigid AND ontime < NEW.ontime AND ontime + INTERVAL '1 minute' * duration > NEW.ontime;
        IF FOUND THEN
            RAISE NOTICE 'Existed act finish later than new act';
            RETURN NULL;
        ELSE 
            RAISE NOTICE 'Existed act DOES NOT finish later than new act';
        END IF;
        SELECT ontime INTO act_time FROM act_gig WHERE gigid = NEW.gigid AND ontime > NEW.ontime AND NEW.ontime + INTERVAL '1 minute' * NEW.duration > ontime;
        IF FOUND THEN
            RAISE NOTICE 'New act finish later than existed act';
            RETURN NULL;
        ELSE 
            RAISE NOTICE 'New act DOES NOT finish later than existed act';
        END IF;
        SELECT ontime INTO act_time FROM act_gig WHERE gigID = NEW.gigID AND ontime = NEW.ontime;
        IF FOUND THEN
            RAISE NOTICE 'New act starts at the same time as existed act';
            RETURN NULL;
        ELSE 
            RAISE NOTICE 'New act DOES NOT start at the same time as existed act';
        END IF;
    RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION act_20mins_gap() --check if existed acts gap from the new act for too long in the same gig(> 20 minutes)--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        act_time TIMESTAMP;
        act_duration INTEGER;
        gig_id INTEGER;
    BEGIN
        SELECT ontime,duration,gigid INTO act_time,act_duration,gig_id FROM act_gig WHERE gigid = NEW.gigid AND ontime < NEW.ontime ORDER BY ontime DESC LIMIT 1; --select the latest act before the new act in the gig--
        IF FOUND THEN
            RAISE NOTICE 'The last act before new act is in gig %, at %, lasts for % minutes',gig_id,act_time,act_duration;
            IF act_time + INTERVAL '1 minute' * (20 + act_duration) < NEW.ontime THEN
                RAISE NOTICE 'The new act gap from last act for too long';
                RETURN NULL;
            ELSE
                RAISE NOTICE 'The new act DO NOT gap from last act for too long';
            END IF;
        END IF;
        SELECT ontime,duration,gigid INTO act_time,act_duration,gig_id FROM act_gig WHERE gigid = NEW.gigid AND ontime > NEW.ontime ORDER BY ontime ASC LIMIT 1; --select the earliest act after the new act in the gig--
        IF FOUND THEN
            RAISE NOTICE 'The first act after new act is in gig %, at %, lasts for % minutes',gig_id,act_time,act_duration;
            IF NEW.ontime + INTERVAL '1 minute' * (20 + NEW.duration) < act_time THEN 
                RAISE NOTICE 'The new act gap from next act for too long';
                RETURN NULL;
            ELSE
                RAISE NOTICE 'The new act DO NOT gap from next act for too long';
            END IF;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION act_in_multiple_gigs() --check if there is a 20-minute gap between new act and existed acts with same actID--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        act_time TIMESTAMP;
        act_duration INTEGER;
        gig_id INTEGER;
        gig_status VARCHAR(20);
    BEGIN
        SELECT ontime INTO act_time FROM act_gig WHERE gigid <> NEW.gigID AND actid = NEW.actid AND ontime = NEW.ontime; --select the act in another gig which starts at the same time with new act--
        IF FOUND THEN
            RAISE NOTICE 'There is a same act performing in another gig at the same time';
            RETURN NULL;
        ELSE
            RAISE NOTICE 'There is not a same act performing in another gig at the same time';
            SELECT ontime,duration,gigid,gigstatus INTO act_time,act_duration,gig_id,gig_status FROM act_gig JOIN gig USING(gigid) WHERE --select the earliest act after the new act in another gig--
                gigstatus = 'GoingAhead' AND 
                gigid <> NEW.gigid AND 
                actid = NEW.actid AND 
                ontime::date = NEW.ontime::date AND 
                ontime::time > NEW.ontime::time
                ORDER BY ontime ASC LIMIT 1;
            IF FOUND THEN
                IF NEW.ontime + INTERVAL '1 minute' * (NEW.duration + 20) > act_time THEN
                    RAISE NOTICE 'Not enough time to get to gig % in 20 minutes', gig_id;
                    RETURN NULL;
                ELSE 
                    RAISE NOTICE 'Enough time to get to gig % in 20 minutes', gig_id;
                END IF;
            END IF;
            SELECT ontime,duration,gigid,gigstatus INTO act_time,act_duration,gig_id,gig_status FROM act_gig JOIN gig USING(gigid) WHERE  --select the latest act before the new act in another gig--
                gigstatus = 'GoingAhead' AND 
                gigid <> NEW.gigid AND 
                actid = NEW.actid AND 
                ontime::date = NEW.ontime::date AND 
                ontime::time < NEW.ontime::time
                ORDER BY ontime DESC LIMIT 1;
            IF FOUND THEN
                IF act_time + INTERVAL '1 minute' * (act_duration + 20) > NEW.ontime THEN
                    RAISE NOTICE 'Not enough time to get to gig % in 20 minutes', NEW.gigid;
                    RETURN NULL;
                ELSE 
                    RAISE NOTICE 'Enough time to get to gig % in 20 minutes', NEW.gigid;
                END IF;
            END IF;
        END IF;
        
    RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION multiple_gigs_venue_sameTime() --check if there is a gig using the same venue at the same time with new gig, if not at the same time, check if there is at least 3-hour gap between these gigs--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        gig_id INTEGER;
        gig_date TIMESTAMP;
        gig_finishtime TIMESTAMP;
    BEGIN
        SELECT gigid INTO gig_id FROM gig WHERE venueid = NEW.venueid AND gigdate = NEW.gigdate;
        IF FOUND THEN
            RAISE NOTICE 'Venues should not be used by multiple gigs at the same time';
            RETURN NULL;
        ELSE
            SELECT gigid, gigdate INTO gig_id, gig_date FROM gig WHERE  --select the latest gig before the new gig in the same venue--
                venueid = NEW.venueid AND 
                gigdate::date = NEW.gigdate::date AND 
                gigdate::time < NEW.gigdate::time AND
                gigstatus = 'GoingAhead'
                ORDER BY gigdate DESC LIMIT 1;
            IF FOUND THEN
                RAISE NOTICE 'Venues are used by multiple gigs % on the same day % but not the same time', gig_id, gig_date;
                SELECT (ontime + INTERVAL '1 minute' * duration) INTO gig_finishtime FROM act_gig WHERE gigid = gig_id ORDER BY ontime DESC LIMIT 1;
                RAISE NOTICE 'The last gig finishes at %', gig_finishtime;
                IF (NEW.gigdate < (gig_finishtime + INTERVAL '1 hour' * 3)) THEN
                    RAISE NOTICE 'There is not enough time for the staff to tidy up the venue until %', (gig_finishtime + INTERVAL '1 hour' * 3);
                    RETURN NULL;
                END IF;
            END IF;
            SELECT gigid, gigdate INTO gig_id, gig_date FROM gig WHERE --select the earliest gig after the new gig in the same venue--
                venueid = NEW.venueid AND 
                gigdate::date = NEW.gigdate::date AND 
                gigdate::time > NEW.gigdate::time AND
                gigstatus = 'GoingAhead'
                ORDER BY gigdate ASC LIMIT 1;
            IF FOUND THEN
                RAISE NOTICE 'Venues are used by multiple gigs % on the same day % but not the same time', gig_id, gig_date;
                RAISE NOTICE 'The first gig after new gig starts at %', gig_date;
                IF ((NEW.gigdate + INTERVAL '1 hour' * 3) > gig_date) THEN
                    RAISE NOTICE 'There is not enough time for the staff to tidy up the venue until %', gig_date;
                    RETURN NULL;
                END IF;
            END IF;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION new_act_3hourGap_gigs() --This function is doing the same thing as the previous one, but the previous one is checking if the gigdate is invalid, this one is checking if  newly inserted act in a gig would be invalid based on the 3-hour gap rule--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        lastAct_Gig TIMESTAMP;
        new_act_gig_date TIMESTAMP;
        venue_id INTEGER;
        gig_id INTEGER;
        existed_gig_date TIMESTAMP;
    BEGIN
        RAISE NOTICE 'new_act_3hourGap_gigs is executed';
            SELECT venueID,gigdate INTO venue_id,new_act_gig_date FROM gig WHERE gigid = NEW.gigid; 
            RAISE NOTICE 'The venue % is used by gig %',venue_id,NEW.gigid;                         --We won't do the one before the gig of new act as it could only happen when we try to insert an act before the gigdate of the gig, but this can't happen
            SELECT gigid,gigdate INTO gig_id,existed_gig_date FROM gig WHERE                        --select the earliest gig after the gig of new act in the same venue--
                venueid = venue_id AND 
                gigdate::date = new_act_gig_date::date AND 
                gigdate::time > new_act_gig_date::time AND
                gigstatus = 'GoingAhead'
                ORDER BY gigdate ASC LIMIT 1;
            IF FOUND THEN
                RAISE NOTICE 'Venues are used by multiple gigs % on the same day % but not the same time', gig_id, existed_gig_date;
                RAISE NOTICE 'The first gig after the gig we are going to insert an act into starts at %', existed_gig_date;
                IF (NEW.ontime + INTERVAL '1 minute' * (180 + NEW.duration) > existed_gig_date) THEN
                    RAISE NOTICE 'There is NOT enough time for the staff to tidy up the venue until the existed gig % starting at %', gig_id,existed_gig_date;
                    RETURN NULL;
                ELSE
                    RAISE NOTICE 'There is enough time for the staff to tidy up the venue until the existed gig % starting at %', gig_id,existed_gig_date;
                END IF;
            END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION act_NoEarlierThan_gigdate() --check if an act starts earlier than the gigdate of its gig--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        gig_date TIMESTAMP;
    BEGIN
        SELECT gigdate INTO gig_date FROM gig WHERE gigid = NEW.gigid;
        IF NEW.ontime < gig_date THEN
            RAISE NOTICE 'Act cannot start earlier than gigdate';
            RETURN NULL;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION firstAct_gig() --check if the first act in an gig starts earlier than the gigdate of its gig--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        existed_actID INTEGER;
        gig_date TIMESTAMP;
    BEGIN
        SELECT actid INTO existed_actID FROM act_gig WHERE gigid = NEW.gigid LIMIT 1;   --check if there are any acts in the gig right now--
        IF NOT FOUND THEN
            RAISE NOTICE 'There is no acts in the gig % right now.',NEW.gigid;
            SELECT gigdate INTO gig_date FROM gig WHERE gigid = NEW.gigid;
            IF NEW.ontime != gig_date THEN
                RAISE NOTICE 'The first act % of the gig does not start at the same time as the gig % start time %',NEW.actid,NEW.gigid,gig_date; --First act of the gig should start at the same time of its gig--
                RETURN NULL;
            END IF;
        END IF;

        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION act_noLaterThan_11_59_pm() --Check if an act finishes later than 11:59 p.m.--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        gig_date TIMESTAMP;
    BEGIN
        SELECT gigdate INTO gig_date FROM gig WHERE gigid = NEW.gigID;
        IF (NEW.ontime + INTERVAL '1 minute' * NEW.duration)::date > gig_date THEN --The trick here is that we can check the act finishes later than 11:59 p.m. by looking at its finish date,--
            RAISE NOTICE 'The new act of gig % goes beyond 11:59 p.m.',NEW.gigid;  --because if it finishes later than 11:59 p.m., its date would be bigger than the gigdate -- 
            RETURN NULL;
        END IF;

        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION ticketsMoreThanCapacity() --Check if the gig sold more tickets more than the capacity of its venue--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        venue_id INTEGER;
        venue_Capacity INTEGER;
        tickets_Sold INTEGER;
    BEGIN
        SELECT venueid INTO venue_id FROM gig WHERE gigid = NEW.gigid;
        SELECT capacity INTO venue_Capacity FROM venue WHERE venueid = venue_id;

        SELECT COUNT(*) INTO tickets_Sold FROM ticket WHERE gigid = NEW.gigid;
        IF tickets_Sold + 1 > venue_Capacity THEN   --If the number of sold tickets + 1 (the new ticket) is bigger than the capacity, then it is invalid--
            RAISE NOTICE 'There should be no more tickets sold in gig % using venue % than the venue capacity %',NEW.gigid,venue_id,venue_Capacity;
            RETURN NULL;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION delete_act_20MinsGap() --Check if the deletion of an act would result in the cancellation of its gig--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        headLineActName VARCHAR(100);
        headlineActID INTEGER;
        gig_headlineActID INTEGER;
        FirstActID INTEGER;
        LastActBeforeDeletedAct TIMESTAMP;
        FirstActAfterDeletedAct TIMESTAMP;
    BEGIN
        SELECT headlineAct_ofGig(OLD.gigid) INTO headLineActName;
        SELECT actid INTO headlineActID FROM Act WHERE actname = headLineActName;
        SELECT actid INTO FirstActID FROM act_gig WHERE gigid = OLD.gigid ORDER BY ontime ASC LIMIT 1;
        RAISE NOTICE 'The deteled actid is %, the headlineAct of the gig is %, the first act of the gig is %',OLD.actid,headlineActID,FirstActID;
        IF headlineActID = OLD.actID OR FirstActID = OLD.actID THEN         --If the deleted act is headline act, cancel the gig--
            UPDATE gig SET gigstatus = 'Cancelled' WHERE gigid = OLD.gigid; --I assume that if the deleted act is the first act, the gig would be cancelled too, because the act after the deleted act would be the new first act, but the new first act wouldn't start at the same time as the gig--
            UPDATE ticket SET Cost = 0 WHERE gigid = OLD.gigid;
            RETURN OLD;
        END IF; 
        SELECT ontime + INTERVAL '1 minute' * duration INTO LastActBeforeDeletedAct FROM act_gig WHERE gigid = OLD.gigid AND ontime < OLD.ontime ORDER BY ontime DESC LIMIT 1; --select the latest act before deleted act in the gig--
        SELECT ontime INTO FirstActAfterDeletedAct FROM act_gig WHERE gigid = OLD.gigid AND ontime > OLD.ontime ORDER BY ontime ASC LIMIT 1;                                   --select the earliest act after deleted act in the gig--
        RAISE NOTICE 'The First Act After Deleted Act starts at %, the Last Act Before Deleted Act finishes at %',FirstActAfterDeletedAct,LastActBeforeDeletedAct;             
        IF LastActBeforeDeletedAct + INTERVAL '1 minute' * 20 < FirstActAfterDeletedAct THEN                                                                                   --If they gap more than 20 minutes, cancel the gig--
            UPDATE gig SET gigstatus = 'Cancelled' WHERE gigid = OLD.gigid;
            UPDATE ticket SET Cost = 0 WHERE gigid = OLD.gigid;
            RETURN OLD;
        END IF;
        RETURN OLD;
    END;
$$;

CREATE OR REPLACE FUNCTION customer_sameName_sameEmail() --Check if the customer always uses the same name and email--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        customer_Name VARCHAR(100);
    BEGIN
        SELECT customerName INTO customer_Name FROM ticket WHERE customerEmail = NEW.customerEmail;
        IF FOUND THEN
            IF customer_Name != NEW.customername THEN
                RAISE NOTICE 'customer should always use the same name and email address when booking ticket';
                RETURN NULL;
            END IF;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION customer_validEmail() --Check if the customer's email is in valid format--
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
    DECLARE
        
    BEGIN
        IF NEW.customerEmail NOT LIKE '%@%' THEN
            RAISE NOTICE 'Invalid email';

            RETURN NULL;
        END IF;
        RETURN NEW;
    END;
$$;

CREATE TRIGGER organise_trigger_1 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION act_overlap();

CREATE TRIGGER organise_trigger_2 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION act_in_multiple_gigs();

CREATE TRIGGER organise_trigger_3 BEFORE INSERT ON gig
FOR EACH ROW
EXECUTE FUNCTION multiple_gigs_venue_sameTime();

CREATE TRIGGER organise_trigger_4 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION act_20mins_gap();

CREATE TRIGGER organise_trigger_5 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION new_act_3hourGap_gigs();

CREATE TRIGGER organise_trigger_6 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION act_NoEarlierThan_gigdate();

CREATE TRIGGER organise_trigger_7 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION firstAct_gig();

CREATE TRIGGER organise_trigger_8 BEFORE INSERT ON act_gig
FOR EACH ROW
EXECUTE FUNCTION act_noLaterThan_11_59_pm();

CREATE TRIGGER organise_trigger_9 BEFORE INSERT ON ticket
FOR EACH ROW
EXECUTE FUNCTION ticketsMoreThanCapacity();

CREATE TRIGGER organise_trigger_10 BEFORE DELETE ON act_gig
FOR EACH ROW
EXECUTE FUNCTION delete_act_20MinsGap();

CREATE TRIGGER trigger_11 BEFORE INSERT ON ticket
FOR EACH ROW
EXECUTE FUNCTION customer_sameName_sameEmail();

CREATE TRIGGER trigger_12 BEFORE INSERT ON ticket
FOR EACH ROW
EXECUTE FUNCTION customer_validEmail();

CREATE OR REPLACE FUNCTION ticketsToSell(gig_ID int)  --Get the tickets needed to sell to be at least able to pay the agreed fees of the specified gig--
RETURNS INTEGER
language plpgsql
AS $$
    DECLARE
        gig_totalActFee INTEGER;
        venue_cost INTEGER;
        price_Sold INTEGER;
        venue_Capacity INTEGER;
        standardTicketPrice INTEGER;
        ticketstoSell INTEGER;
        tickets_Sold INTEGER;
    BEGIN
        SELECT SUM(actfee) INTO gig_totalActFee FROM act_gig WHERE gigID = gig_ID;
        SELECT hirecost INTO venue_cost FROM venue WHERE venueID = (SELECT venueID FROM gig WHERE gigID = gig_ID);
        SELECT COUNT(*) INTO tickets_Sold FROM ticket WHERE gigID = gig_ID;
        SELECT SUM(cost) INTO price_Sold FROM ticket WHERE gigID = gig_ID;
        SELECT price INTO standardTicketPrice FROM gig_ticket WHERE pricetype = 'A';
        IF (tickets_Sold = 0) THEN
            RAISE NOTICE '% tickets sold for this gig', tickets_Sold;
            ticketstoSell = ceil(((gig_totalActFee + venue_cost) / standardTicketPrice::float));
        ELSE 
            ticketstoSell = ceil(((gig_totalActFee + venue_cost - price_Sold) / standardTicketPrice::float));
            RAISE NOTICE '% tickets sold for this gig', tickets_Sold;
        END IF;
        RETURN ticketstoSell;
    END;
$$;

CREATE OR REPLACE FUNCTION headlineAct_ofGig(select_gig_ID int) --Get the headline act of the specified gig--
RETURNS VARCHAR(100)
language plpgsql
AS $$
    DECLARE
        headlineActTime TIMESTAMP;
        headlineActID INTEGER;
        headlineActName VARCHAR(100);
        gig_ID INTEGER;
    BEGIN
        SELECT max(ontime) INTO headlineActTime FROM act_gig WHERE gigID = select_gig_ID; --headlineact of a gig is its final act or only act--
        SELECT actID INTO headlineActID FROM act_gig WHERE ontime = headlineActTime;
        SELECT actname INTO headlineActName FROM Act WHERE actID = headlineActID;
        
        RETURN headlineActName;
    END;
$$;

CREATE OR REPLACE VIEW op6_view1 AS             --Get the number of tickets sold by each act as the headline act of a gig in each year--
    SELECT headlineact_ofgig(gigid),'Total'::text AS year,SUM(count) FROM gig 
    JOIN (SELECT gigid,COUNT(*) FROM ticket GROUP BY gigid) AS ts USING(gigid) 
    WHERE gig.gigstatus = 'GoingAhead' GROUP BY headlineact_ofgig ORDER BY sum;

CREATE OR REPLACE VIEW op6_view2 AS             --Get the number of tickets each customer bought for each act as the headline act of a gig in each year--
    SELECT headlineact_ofgig(gigid),EXTRACT(YEAR FROM gigdate)::text as year,sum(ts.count) FROM gig 
    JOIN (SELECT gigid,COUNT(*) FROM ticket GROUP BY gigid) AS ts USING(gigid) 
    WHERE gig.gigstatus = 'GoingAhead' GROUP BY headlineact_ofgig,year;

CREATE OR REPLACE VIEW op6_view3 AS             --Get the total number of tickets sold by each act as the headline act of a gig--
    SELECT headlineact_ofgig(gigid),SUM(count) FROM gig 
    JOIN (SELECT gigid,COUNT(*) FROM ticket GROUP BY gigid) AS ts USING(gigid) 
    WHERE gig.gigstatus = 'GoingAhead' GROUP BY headlineact_ofgig;

CREATE OR REPLACE VIEW op6_result_view AS       --UNION op6_view1 and op7_view2 to get the table including the total number of tickets, and join op6_view3 to order the table by total number of tickets sold by each act--
    SELECT ts.headlineact_ofgig AS "Act Name",ts.year AS "Year",ts.sum AS "Total Tickets Sold" FROM op6_view3
    JOIN(select * from op6_view1 UNION select * from op6_view2) AS ts USING(headlineact_ofgig) 
    ORDER BY op6_view3.sum,year;

CREATE OR REPLACE VIEW op7_view1 AS             --Get the number of distinct years that each act performing as a headline act--
    SELECT COUNT(EXTRACT (YEAR FROM gigdate)),headlineact_ofgig(gigid) FROM gig
    WHERE gigstatus = 'GoingAhead' 
    GROUP BY headlineact_ofgig 
    ORDER BY headlineact_ofgig;

CREATE OR REPLACE VIEW op7_view2 AS             --Get the number of distinct years that each customer bought ticket(s) for the act performing as a headline act--
    SELECT COUNT(DISTINCT EXTRACT(YEAR FROM gigdate)),customername,headlineact_ofgig(gigid) FROM ticket 
    JOIN gig USING(gigid) 
    WHERE gigstatus = 'GoingAhead'
    GROUP BY headlineact_ofgig,customername;

CREATE OR REPLACE VIEW op7_result_view AS        --If a customer is not a regular customer of an act, then the number of distinct years that he bought ticket(s) for that act must be less than the one that the act performing as a headline act--
    SELECT headlineact_ofgig,COALESCE(customername,'[None]') FROM op7_view1 
    LEFT JOIN op7_view2 USING(headlineact_ofgig) --LEFT JOIN because we need to keep the act for which no customer is a regular customer--
    WHERE op7_view1.count = op7_view2.count OR op7_view2.count IS NULL --We need to keep the row which no customer is a regular customer for that act--
    ORDER BY headlineact_ofgig,op7_view1.count;

CREATE OR REPLACE VIEW op8_view1 AS             
    SELECT actname,venuename,ceil((hirecost + standardfee) / (SELECT AVG(Cost) FROM ticket JOIN gig USING(gigid) WHERE gigstatus = 'GoingAhead')) AS tickets  
    FROM act CROSS JOIN venue;                  --We do CROSS JOIN to get every combination of the venue and the act, and then we calculate the sum of their hirecost and standardfee--
                                                --Divide it by the average ticket price of sold tickets to get the ticket needed to sell to be able to pay the sum fee of venuecost and actfee--

CREATE OR REPLACE VIEW op8_result_view AS       --We JOIN op8_view1 with venue to get venue.capacity, then we exclude the rows where the tickets needed to sell is bigger than the venue capacity to get the result table of Option 8--
    SELECT venuename,actname,tickets FROM op8_view1 
    JOIN venue USING(venuename) 
    WHERE op8_view1.tickets <= venue.capacity 
    ORDER BY venuename,tickets DESC;


