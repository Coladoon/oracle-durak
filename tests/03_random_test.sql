PROMPT Проверка детерминированного seed и порядка колоды

DECLARE
    v_key_1       RAW(32);
    v_key_2       RAW(32);
    v_key_other   RAW(32);
    v_daily_1     VARCHAR2(64);
    v_daily_2     VARCHAR2(64);
    v_order_1     VARCHAR2(4000);
    v_order_2     VARCHAR2(4000);
    v_order_other VARCHAR2(4000);
    v_position    NUMBER;
BEGIN
    v_key_1 := durak_random.card_shuffle_key(
        'test-seed', 36, 'PODKIDNOY', durak_random.c_shuffle_version, '6C'
    );
    v_key_2 := durak_random.card_shuffle_key(
        'test-seed', 36, 'PODKIDNOY', durak_random.c_shuffle_version, '6C'
    );
    v_key_other := durak_random.card_shuffle_key(
        'other-seed', 36, 'PODKIDNOY', durak_random.c_shuffle_version, '6C'
    );

    durak_test.assert_raw_equal(
        'Одинаковый seed даёт одинаковый ключ карты',
        v_key_1,
        v_key_2
    );
    durak_test.assert_raw_not_equal(
        'Другой seed меняет ключ карты',
        v_key_1,
        v_key_other
    );

    v_daily_1 := durak_random.daily_seed(
        DATE '2026-08-29', 36, 'PODKIDNOY', 'LOWEST_TRUMP', 'RULES-V1'
    );
    v_daily_2 := durak_random.daily_seed(
        DATE '2026-08-29', 36, 'PODKIDNOY', 'LOWEST_TRUMP', 'RULES-V1'
    );
    durak_test.assert_text(
        'Daily seed воспроизводится по дате и правилам',
        v_daily_1,
        v_daily_2
    );

    v_position := durak_random.seeded_position('test-seed', 'FIRST-PLAYER', 6);
    durak_test.assert_between(
        'Seeded-позиция входит в диапазон игроков',
        v_position,
        1,
        6
    );

    SELECT LISTAGG(card_code, ',') WITHIN GROUP (
               ORDER BY RAWTOHEX(
                   durak_random.card_shuffle_key(
                       'test-seed',
                       36,
                       'PODKIDNOY',
                       durak_random.c_shuffle_version,
                       card_code
                   )
               ), card_id
           )
    INTO v_order_1
    FROM durak_card
    WHERE included_in_36 = 'Y';

    SELECT LISTAGG(card_code, ',') WITHIN GROUP (
               ORDER BY RAWTOHEX(
                   durak_random.card_shuffle_key(
                       'test-seed',
                       36,
                       'PODKIDNOY',
                       durak_random.c_shuffle_version,
                       card_code
                   )
               ), card_id
           )
    INTO v_order_2
    FROM durak_card
    WHERE included_in_36 = 'Y';

    SELECT LISTAGG(card_code, ',') WITHIN GROUP (
               ORDER BY RAWTOHEX(
                   durak_random.card_shuffle_key(
                       'other-seed',
                       36,
                       'PODKIDNOY',
                       durak_random.c_shuffle_version,
                       card_code
                   )
               ), card_id
           )
    INTO v_order_other
    FROM durak_card
    WHERE included_in_36 = 'Y';

    durak_test.assert_text(
        'Полный порядок колоды повторяется с тем же seed',
        v_order_1,
        v_order_2
    );

    IF v_order_1 <> v_order_other THEN
        durak_test.pass('Другой seed меняет порядок колоды');
    ELSE
        durak_test.fail(
            'Другой seed меняет порядок колоды',
            'для двух контрольных seed получился одинаковый порядок'
        );
    END IF;
END;
/
