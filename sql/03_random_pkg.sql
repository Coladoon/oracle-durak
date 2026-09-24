PROMPT Создание пакета DURAK_RANDOM

CREATE OR REPLACE PACKAGE durak_random AUTHID DEFINER AS
    c_shuffle_version CONSTANT VARCHAR2(20) := 'SHA256-V1';

    FUNCTION generated_seed RETURN VARCHAR2;

    FUNCTION normalize_seed (
        p_seed_text IN VARCHAR2
    ) RETURN VARCHAR2 DETERMINISTIC;

    FUNCTION hash_text (
        p_text IN VARCHAR2
    ) RETURN RAW DETERMINISTIC;

    FUNCTION game_seed_hash (
        p_seed_text       IN VARCHAR2,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_shuffle_version IN VARCHAR2 DEFAULT c_shuffle_version
    ) RETURN RAW DETERMINISTIC;

    FUNCTION card_shuffle_key (
        p_seed_text       IN VARCHAR2,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_shuffle_version IN VARCHAR2,
        p_card_code       IN VARCHAR2
    ) RETURN RAW DETERMINISTIC;

    FUNCTION daily_seed (
        p_daily_date      IN DATE,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_first_move_mode IN VARCHAR2,
        p_rules_version   IN VARCHAR2
    ) RETURN VARCHAR2 DETERMINISTIC;

    FUNCTION seeded_position (
        p_seed_text   IN VARCHAR2,
        p_purpose     IN VARCHAR2,
        p_upper_bound IN NUMBER
    ) RETURN NUMBER DETERMINISTIC;
END durak_random;
/

CREATE OR REPLACE PACKAGE BODY durak_random AS
    FUNCTION encode_part (
        p_value IN VARCHAR2
    ) RETURN VARCHAR2 DETERMINISTIC IS
        v_raw RAW(32767);
    BEGIN
        IF p_value IS NULL THEN
            RETURN '0:';
        END IF;

        v_raw := UTL_I18N.STRING_TO_RAW(p_value, 'AL32UTF8');
        RETURN TO_CHAR(UTL_RAW.LENGTH(v_raw), 'FM9999999990') || ':' || p_value;
    END encode_part;

    FUNCTION canonical_number (
        p_value IN NUMBER
    ) RETURN VARCHAR2 DETERMINISTIC IS
    BEGIN
        RETURN TO_CHAR(
            p_value,
            'TM9',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END canonical_number;

    PROCEDURE validate_deck_and_variant (
        p_deck_size    IN NUMBER,
        p_game_variant IN VARCHAR2
    ) IS
    BEGIN
        IF p_deck_size IS NULL OR p_deck_size NOT IN (36, 52) THEN
            RAISE_APPLICATION_ERROR(-20521, 'Размер колоды должен быть 36 или 52.');
        END IF;

        IF p_game_variant IS NULL
           OR UPPER(TRIM(p_game_variant)) NOT IN ('PODKIDNOY', 'PEREVODNOY') THEN
            RAISE_APPLICATION_ERROR(-20522, 'Неизвестный вариант игры.');
        END IF;
    END validate_deck_and_variant;

    FUNCTION generated_seed RETURN VARCHAR2 IS
    BEGIN
        RETURN RAWTOHEX(SYS_GUID());
    END generated_seed;

    FUNCTION normalize_seed (
        p_seed_text IN VARCHAR2
    ) RETURN VARCHAR2 DETERMINISTIC IS
        v_seed VARCHAR2(32767);
    BEGIN
        v_seed := TRIM(p_seed_text);

        IF v_seed IS NULL THEN
            RAISE_APPLICATION_ERROR(-20520, 'Seed не может быть пустым.');
        END IF;

        IF LENGTHB(v_seed) > 128 THEN
            RAISE_APPLICATION_ERROR(-20523, 'Seed не должен превышать 128 байт.');
        END IF;

        RETURN v_seed;
    END normalize_seed;

    FUNCTION hash_text (
        p_text IN VARCHAR2
    ) RETURN RAW DETERMINISTIC IS
        v_hash RAW(32);
    BEGIN
        IF p_text IS NULL THEN
            RAISE_APPLICATION_ERROR(-20524, 'Нельзя вычислить hash пустого текста.');
        END IF;

        SELECT STANDARD_HASH(
                   UTL_I18N.STRING_TO_RAW(p_text, 'AL32UTF8'),
                   'SHA256'
               )
        INTO v_hash
        FROM dual;

        RETURN v_hash;
    END hash_text;

    FUNCTION game_seed_hash (
        p_seed_text       IN VARCHAR2,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_shuffle_version IN VARCHAR2 DEFAULT c_shuffle_version
    ) RETURN RAW DETERMINISTIC IS
        v_seed    VARCHAR2(128);
        v_variant VARCHAR2(12);
        v_version VARCHAR2(20);
        v_payload VARCHAR2(1000);
    BEGIN
        validate_deck_and_variant(p_deck_size, p_game_variant);
        v_seed    := normalize_seed(p_seed_text);
        v_variant := UPPER(TRIM(p_game_variant));
        v_version := UPPER(TRIM(p_shuffle_version));

        IF v_version IS NULL THEN
            RAISE_APPLICATION_ERROR(-20525, 'Версия перемешивания не задана.');
        END IF;

        v_payload := encode_part('DURAK-GAME')
            || encode_part(v_version)
            || encode_part(canonical_number(p_deck_size))
            || encode_part(v_variant)
            || encode_part(v_seed);

        RETURN hash_text(v_payload);
    END game_seed_hash;

    FUNCTION card_shuffle_key (
        p_seed_text       IN VARCHAR2,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_shuffle_version IN VARCHAR2,
        p_card_code       IN VARCHAR2
    ) RETURN RAW DETERMINISTIC IS
        v_seed      VARCHAR2(128);
        v_variant   VARCHAR2(12);
        v_version   VARCHAR2(20);
        v_card_code VARCHAR2(3);
        v_payload   VARCHAR2(1000);
    BEGIN
        validate_deck_and_variant(p_deck_size, p_game_variant);
        v_seed      := normalize_seed(p_seed_text);
        v_variant   := UPPER(TRIM(p_game_variant));
        v_version   := UPPER(TRIM(p_shuffle_version));
        v_card_code := UPPER(TRIM(p_card_code));

        IF v_version IS NULL OR v_card_code IS NULL THEN
            RAISE_APPLICATION_ERROR(-20526, 'Версия и код карты обязательны.');
        END IF;

        v_payload := encode_part('DURAK-SHUFFLE-CARD')
            || encode_part(v_version)
            || encode_part(canonical_number(p_deck_size))
            || encode_part(v_variant)
            || encode_part(v_seed)
            || encode_part(v_card_code);

        RETURN hash_text(v_payload);
    END card_shuffle_key;

    FUNCTION daily_seed (
        p_daily_date      IN DATE,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_first_move_mode IN VARCHAR2,
        p_rules_version   IN VARCHAR2
    ) RETURN VARCHAR2 DETERMINISTIC IS
        v_date       VARCHAR2(8);
        v_first      VARCHAR2(20);
        v_rules      VARCHAR2(20);
        v_payload    VARCHAR2(1000);
    BEGIN
        IF p_daily_date IS NULL THEN
            RAISE_APPLICATION_ERROR(-20527, 'Дата Daily не задана.');
        END IF;

        validate_deck_and_variant(p_deck_size, p_game_variant);
        v_first := UPPER(TRIM(p_first_move_mode));
        v_rules := UPPER(TRIM(p_rules_version));

        IF v_first IS NULL OR v_first NOT IN ('LOWEST_TRUMP', 'SEEDED_RANDOM') THEN
            RAISE_APPLICATION_ERROR(-20528, 'Неизвестный способ первого хода.');
        END IF;

        IF v_rules IS NULL THEN
            RAISE_APPLICATION_ERROR(-20529, 'Версия правил Daily не задана.');
        END IF;

        v_date := TO_CHAR(
            TRUNC(p_daily_date),
            'YYYYMMDD',
            'NLS_DATE_LANGUAGE=English NLS_CALENDAR=Gregorian'
        );

        v_payload := encode_part('DURAK-DAILY')
            || encode_part(v_date)
            || encode_part(canonical_number(p_deck_size))
            || encode_part(UPPER(TRIM(p_game_variant)))
            || encode_part(v_first)
            || encode_part(v_rules);

        RETURN RAWTOHEX(hash_text(v_payload));
    END daily_seed;

    FUNCTION seeded_position (
        p_seed_text   IN VARCHAR2,
        p_purpose     IN VARCHAR2,
        p_upper_bound IN NUMBER
    ) RETURN NUMBER DETERMINISTIC IS
        v_hex      VARCHAR2(64);
        v_value    NUMBER := 0;
        v_digit    PLS_INTEGER;
        v_purpose  VARCHAR2(200);
    BEGIN
        IF p_upper_bound IS NULL
           OR p_upper_bound < 1
           OR p_upper_bound <> TRUNC(p_upper_bound) THEN
            RAISE_APPLICATION_ERROR(-20530, 'Верхняя граница должна быть целым числом больше нуля.');
        END IF;

        v_purpose := TRIM(p_purpose);
        IF v_purpose IS NULL THEN
            RAISE_APPLICATION_ERROR(-20531, 'Назначение seeded-выбора не задано.');
        END IF;

        v_hex := SUBSTR(
            RAWTOHEX(
                hash_text(
                    encode_part('DURAK-SEEDED-POSITION')
                    || encode_part(normalize_seed(p_seed_text))
                    || encode_part(v_purpose)
                )
            ),
            1,
            8
        );

        FOR i IN 1 .. LENGTH(v_hex) LOOP
            v_digit := INSTR('0123456789ABCDEF', SUBSTR(v_hex, i, 1)) - 1;
            v_value := v_value * 16 + v_digit;
        END LOOP;

        RETURN MOD(v_value, p_upper_bound) + 1;
    END seeded_position;
END durak_random;
/

SHOW ERRORS PACKAGE durak_random
SHOW ERRORS PACKAGE BODY durak_random
