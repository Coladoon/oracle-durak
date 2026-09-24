PROMPT Проверка справочника карт

DECLARE
    v_value NUMBER;
    v_min   NUMBER;
    v_max   NUMBER;
    v_text  VARCHAR2(10);
BEGIN
    SELECT COUNT(*) INTO v_value FROM durak_card;
    durak_test.assert_number('В справочнике 52 карты', 52, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_card
    WHERE included_in_36 = 'Y';
    durak_test.assert_number('В короткой колоде 36 карт', 36, v_value);

    SELECT MIN(suit_count), MAX(suit_count)
    INTO v_min, v_max
    FROM (
        SELECT suit_code, COUNT(*) AS suit_count
        FROM durak_card
        GROUP BY suit_code
    );
    durak_test.assert_number('В каждой масти не меньше 13 карт', 13, v_min);
    durak_test.assert_number('В каждой масти не больше 13 карт', 13, v_max);

    SELECT COUNT(DISTINCT card_code) INTO v_value FROM durak_card;
    durak_test.assert_number('Коды всех карт уникальны', 52, v_value);

    SELECT card_code INTO v_text
    FROM durak_card
    WHERE rank_value = 10 AND suit_code = 'H';
    durak_test.assert_text('Код десятки червей', '10H', v_text);

    SELECT card_code INTO v_text
    FROM durak_card
    WHERE rank_value = 14 AND suit_code = 'S';
    durak_test.assert_text('Код пикового туза', 'AS', v_text);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_card
    WHERE included_in_36 = 'Y'
      AND rank_value < 6;
    durak_test.assert_number('В колоде 36 нет рангов 2..5', 0, v_value);
END;
/
