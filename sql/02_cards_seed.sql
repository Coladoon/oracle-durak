PROMPT Заполнение справочника карт

INSERT ALL
    INTO durak_card VALUES ( 1,  '2C',  '2',  2, 'C', 'N',  1)
    INTO durak_card VALUES ( 2,  '3C',  '3',  3, 'C', 'N',  2)
    INTO durak_card VALUES ( 3,  '4C',  '4',  4, 'C', 'N',  3)
    INTO durak_card VALUES ( 4,  '5C',  '5',  5, 'C', 'N',  4)
    INTO durak_card VALUES ( 5,  '6C',  '6',  6, 'C', 'Y',  5)
    INTO durak_card VALUES ( 6,  '7C',  '7',  7, 'C', 'Y',  6)
    INTO durak_card VALUES ( 7,  '8C',  '8',  8, 'C', 'Y',  7)
    INTO durak_card VALUES ( 8,  '9C',  '9',  9, 'C', 'Y',  8)
    INTO durak_card VALUES ( 9, '10C', '10', 10, 'C', 'Y',  9)
    INTO durak_card VALUES (10,  'JC',  'J', 11, 'C', 'Y', 10)
    INTO durak_card VALUES (11,  'QC',  'Q', 12, 'C', 'Y', 11)
    INTO durak_card VALUES (12,  'KC',  'K', 13, 'C', 'Y', 12)
    INTO durak_card VALUES (13,  'AC',  'A', 14, 'C', 'Y', 13)
    INTO durak_card VALUES (14,  '2D',  '2',  2, 'D', 'N', 14)
    INTO durak_card VALUES (15,  '3D',  '3',  3, 'D', 'N', 15)
    INTO durak_card VALUES (16,  '4D',  '4',  4, 'D', 'N', 16)
    INTO durak_card VALUES (17,  '5D',  '5',  5, 'D', 'N', 17)
    INTO durak_card VALUES (18,  '6D',  '6',  6, 'D', 'Y', 18)
    INTO durak_card VALUES (19,  '7D',  '7',  7, 'D', 'Y', 19)
    INTO durak_card VALUES (20,  '8D',  '8',  8, 'D', 'Y', 20)
    INTO durak_card VALUES (21,  '9D',  '9',  9, 'D', 'Y', 21)
    INTO durak_card VALUES (22, '10D', '10', 10, 'D', 'Y', 22)
    INTO durak_card VALUES (23,  'JD',  'J', 11, 'D', 'Y', 23)
    INTO durak_card VALUES (24,  'QD',  'Q', 12, 'D', 'Y', 24)
    INTO durak_card VALUES (25,  'KD',  'K', 13, 'D', 'Y', 25)
    INTO durak_card VALUES (26,  'AD',  'A', 14, 'D', 'Y', 26)
    INTO durak_card VALUES (27,  '2H',  '2',  2, 'H', 'N', 27)
    INTO durak_card VALUES (28,  '3H',  '3',  3, 'H', 'N', 28)
    INTO durak_card VALUES (29,  '4H',  '4',  4, 'H', 'N', 29)
    INTO durak_card VALUES (30,  '5H',  '5',  5, 'H', 'N', 30)
    INTO durak_card VALUES (31,  '6H',  '6',  6, 'H', 'Y', 31)
    INTO durak_card VALUES (32,  '7H',  '7',  7, 'H', 'Y', 32)
    INTO durak_card VALUES (33,  '8H',  '8',  8, 'H', 'Y', 33)
    INTO durak_card VALUES (34,  '9H',  '9',  9, 'H', 'Y', 34)
    INTO durak_card VALUES (35, '10H', '10', 10, 'H', 'Y', 35)
    INTO durak_card VALUES (36,  'JH',  'J', 11, 'H', 'Y', 36)
    INTO durak_card VALUES (37,  'QH',  'Q', 12, 'H', 'Y', 37)
    INTO durak_card VALUES (38,  'KH',  'K', 13, 'H', 'Y', 38)
    INTO durak_card VALUES (39,  'AH',  'A', 14, 'H', 'Y', 39)
    INTO durak_card VALUES (40,  '2S',  '2',  2, 'S', 'N', 40)
    INTO durak_card VALUES (41,  '3S',  '3',  3, 'S', 'N', 41)
    INTO durak_card VALUES (42,  '4S',  '4',  4, 'S', 'N', 42)
    INTO durak_card VALUES (43,  '5S',  '5',  5, 'S', 'N', 43)
    INTO durak_card VALUES (44,  '6S',  '6',  6, 'S', 'Y', 44)
    INTO durak_card VALUES (45,  '7S',  '7',  7, 'S', 'Y', 45)
    INTO durak_card VALUES (46,  '8S',  '8',  8, 'S', 'Y', 46)
    INTO durak_card VALUES (47,  '9S',  '9',  9, 'S', 'Y', 47)
    INTO durak_card VALUES (48, '10S', '10', 10, 'S', 'Y', 48)
    INTO durak_card VALUES (49,  'JS',  'J', 11, 'S', 'Y', 49)
    INTO durak_card VALUES (50,  'QS',  'Q', 12, 'S', 'Y', 50)
    INTO durak_card VALUES (51,  'KS',  'K', 13, 'S', 'Y', 51)
    INTO durak_card VALUES (52,  'AS',  'A', 14, 'S', 'Y', 52)
SELECT 1 FROM dual;

DECLARE
    v_total       PLS_INTEGER;
    v_deck36      PLS_INTEGER;
    v_bad_suits   PLS_INTEGER;
    v_bad_codes   PLS_INTEGER;
BEGIN
    SELECT COUNT(*),
           SUM(CASE WHEN included_in_36 = 'Y' THEN 1 ELSE 0 END)
    INTO v_total, v_deck36
    FROM durak_card;

    SELECT COUNT(*)
    INTO v_bad_suits
    FROM (
        SELECT suit_code
        FROM durak_card
        GROUP BY suit_code
        HAVING COUNT(*) <> 13
    );

    SELECT COUNT(*)
    INTO v_bad_codes
    FROM durak_card
    WHERE card_code <> rank_code || suit_code
       OR (included_in_36 = 'Y' AND rank_value < 6)
       OR (included_in_36 = 'N' AND rank_value >= 6);

    IF v_total <> 52 OR v_deck36 <> 36 OR v_bad_suits <> 0 OR v_bad_codes <> 0 THEN
        RAISE_APPLICATION_ERROR(-20510, 'Справочник карт заполнен некорректно.');
    END IF;
END;
/

COMMIT;
PROMPT Справочник карт: 52 карты, из них 36 входят в короткую колоду
