PROMPT Создание публичного пакета DURAK_API

CREATE OR REPLACE PACKAGE durak_api AUTHID DEFINER AS
    PROCEDURE register_player (
        p_player_id   OUT NUMBER,
        p_message     OUT VARCHAR2,
        p_display_name IN VARCHAR2,
        p_locale_code IN VARCHAR2 DEFAULT 'ru-RU',
        p_time_zone_name IN VARCHAR2 DEFAULT 'Europe/Moscow'
    );

    PROCEDURE current_player (
        p_player_id OUT NUMBER,
        p_message   OUT VARCHAR2
    );

    PROCEDURE current_game (
        p_game_id OUT NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE create_game (
        p_game_id              OUT NUMBER,
        p_message              OUT VARCHAR2,
        p_deck_size            IN NUMBER DEFAULT 36,
        p_game_variant         IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode      IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs            IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec     IN NUMBER DEFAULT 60,
        p_idle_timeout_min     IN NUMBER DEFAULT 30,
        p_seed_text            IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE create_daily_game (
        p_game_id              OUT NUMBER,
        p_daily_id             OUT NUMBER,
        p_message              OUT VARCHAR2,
        p_daily_date           IN DATE DEFAULT NULL,
        p_deck_size            IN NUMBER DEFAULT 36,
        p_game_variant         IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode      IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs            IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec     IN NUMBER DEFAULT 60,
        p_idle_timeout_min     IN NUMBER DEFAULT 30,
        p_rules_version        IN VARCHAR2 DEFAULT 'RULES-V1'
    );

    PROCEDURE join_game (
        p_game_id IN NUMBER,
        p_seat_no OUT NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE start_game (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE attack (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    );

    PROCEDURE defend (
        p_game_id           IN NUMBER,
        p_defense_card_code IN VARCHAR2,
        p_message           OUT VARCHAR2,
        p_pair_no           IN NUMBER DEFAULT NULL
    );

    PROCEDURE throw_in (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    );

    PROCEDURE pass_throw (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE take_cards (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE transfer_attack (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    );

    PROCEDURE heartbeat (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    );

    PROCEDURE cancel_game (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    );

END durak_api;
/

CREATE OR REPLACE PACKAGE BODY durak_api AS
    FUNCTION session_username RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
    END session_username;

    FUNCTION required_player_id RETURN NUMBER IS
        v_player_id durak_player.player_id%TYPE;
        v_username  durak_player.db_username%TYPE := session_username;
    BEGIN
        SELECT player_id
        INTO v_player_id
        FROM durak_player
        WHERE db_username = v_username;

        RETURN v_player_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20801,
                'Текущий Oracle-пользователь не зарегистрирован. '
                || 'Сначала вызовите DURAK_API.REGISTER_PLAYER.'
            );
    END required_player_id;

    FUNCTION friendly_error (
        p_error_message IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_separator PLS_INTEGER;
    BEGIN
        v_separator := INSTR(p_error_message, ': ');
        IF v_separator > 0 THEN
            RETURN SUBSTR(p_error_message, v_separator + 2, 900);
        END IF;
        RETURN SUBSTR(p_error_message, 1, 900);
    END friendly_error;

    FUNCTION is_business_error (
        p_error_code IN NUMBER
    ) RETURN BOOLEAN IS
    BEGIN
        RETURN p_error_code BETWEEN -20999 AND -20000;
    END is_business_error;

    PROCEDURE success (
        p_text    IN VARCHAR2,
        p_message OUT VARCHAR2
    ) IS
    BEGIN
        p_message := 'УСПЕШНО: ' || p_text;
        DBMS_OUTPUT.PUT_LINE(p_message);
    END success;

    PROCEDURE record_failure (
        p_game_id       IN NUMBER,
        p_player_id     IN NUMBER,
        p_action_type   IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_message IN VARCHAR2,
        p_message       OUT VARCHAR2
    ) IS
    BEGIN
        durak_engine.log_rejection(
            p_game_id       => p_game_id,
            p_player_id     => p_player_id,
            p_db_username   => session_username,
            p_action_type   => p_action_type,
            p_error_code    => p_error_code,
            p_error_message => p_error_message
        );

        p_message := 'ОТКАЗ: ' || friendly_error(p_error_message);
        DBMS_OUTPUT.PUT_LINE(p_message);
    END record_failure;

    FUNCTION ensure_daily (
        p_daily_date      IN DATE,
        p_deck_size       IN NUMBER,
        p_game_variant    IN VARCHAR2,
        p_first_move_mode IN VARCHAR2,
        p_rules_version   IN VARCHAR2,
        p_seed_text       OUT VARCHAR2
    ) RETURN NUMBER IS
        v_daily_id durak_daily.daily_id%TYPE;
        v_date     DATE := TRUNC(NVL(p_daily_date, CURRENT_DATE));
        v_variant  VARCHAR2(12) := UPPER(TRIM(p_game_variant));
        v_first    VARCHAR2(20) := UPPER(TRIM(p_first_move_mode));
        v_rules    VARCHAR2(20) := UPPER(TRIM(p_rules_version));
    BEGIN
        IF v_rules IS NULL OR LENGTHB(v_rules) > 20 THEN
            RAISE_APPLICATION_ERROR(
                -20805,
                'Версия правил Daily должна занимать от 1 до 20 байт.'
            );
        END IF;

        p_seed_text := durak_random.daily_seed(
            p_daily_date      => v_date,
            p_deck_size       => p_deck_size,
            p_game_variant    => v_variant,
            p_first_move_mode => v_first,
            p_rules_version   => v_rules
        );

        BEGIN
            SELECT daily_id, seed_text
            INTO v_daily_id, p_seed_text
            FROM durak_daily
            WHERE daily_date = v_date
              AND deck_size = p_deck_size
              AND game_variant = v_variant
              AND first_move_mode = v_first
              AND rules_version = v_rules;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                BEGIN
                    v_daily_id := durak_id_seq.NEXTVAL;
                    INSERT INTO durak_daily (
                        daily_id,
                        daily_date,
                        deck_size,
                        game_variant,
                        first_move_mode,
                        seed_text,
                        config_hash,
                        rules_version
                    ) VALUES (
                        v_daily_id,
                        v_date,
                        p_deck_size,
                        v_variant,
                        v_first,
                        p_seed_text,
                        durak_random.hash_text(p_seed_text),
                        v_rules
                    );
                EXCEPTION
                    WHEN DUP_VAL_ON_INDEX THEN
                        SELECT daily_id, seed_text
                        INTO v_daily_id, p_seed_text
                        FROM durak_daily
                        WHERE daily_date = v_date
                          AND deck_size = p_deck_size
                          AND game_variant = v_variant
                          AND first_move_mode = v_first
                          AND rules_version = v_rules;
                END;
        END;

        RETURN v_daily_id;
    END ensure_daily;

    PROCEDURE register_player (
        p_player_id    OUT NUMBER,
        p_message      OUT VARCHAR2,
        p_display_name IN VARCHAR2,
        p_locale_code  IN VARCHAR2 DEFAULT 'ru-RU',
        p_time_zone_name IN VARCHAR2 DEFAULT 'Europe/Moscow'
    ) IS
        v_code    NUMBER;
        v_error   VARCHAR2(1000);
        v_name    VARCHAR2(100) := TRIM(p_display_name);
        v_locale  VARCHAR2(20) := TRIM(p_locale_code);
        v_tz      VARCHAR2(64) := TRIM(p_time_zone_name);
        v_username durak_player.db_username%TYPE := session_username;
    BEGIN
        SAVEPOINT durak_api_call;

        IF v_name IS NULL OR LENGTHB(v_name) > 100 THEN
            RAISE_APPLICATION_ERROR(-20802, 'Имя должно занимать от 1 до 100 байт.');
        END IF;
        IF v_locale IS NULL OR LENGTHB(v_locale) > 20 THEN
            RAISE_APPLICATION_ERROR(-20803, 'Некорректный код локали.');
        END IF;
        IF v_tz IS NULL OR LENGTHB(v_tz) > 64 THEN
            RAISE_APPLICATION_ERROR(-20804, 'Некорректное имя часового пояса.');
        END IF;

        BEGIN
            SELECT player_id
            INTO p_player_id
            FROM durak_player
            WHERE db_username = v_username;

            success(
                'пользователь уже зарегистрирован, PLAYER_ID=' || p_player_id || '.',
                p_message
            );
            COMMIT;
            RETURN;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;

        p_player_id := durak_id_seq.NEXTVAL;
        INSERT INTO durak_player (
            player_id,
            db_username,
            display_name,
            player_type,
            locale_code,
            time_zone_name
        ) VALUES (
            p_player_id,
            v_username,
            v_name,
            'HUMAN',
            v_locale,
            v_tz
        );

        COMMIT;
        success('игрок зарегистрирован, PLAYER_ID=' || p_player_id || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            p_player_id := NULL;
            record_failure(NULL, NULL, 'REGISTER_PLAYER', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END register_player;

    PROCEDURE current_player (
        p_player_id OUT NUMBER,
        p_message   OUT VARCHAR2
    ) IS
        v_code  NUMBER;
        v_error VARCHAR2(1000);
    BEGIN
        p_player_id := required_player_id;
        success('текущий PLAYER_ID=' || p_player_id || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            p_player_id := NULL;
            record_failure(NULL, NULL, 'CURRENT_PLAYER', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END current_player;

    PROCEDURE current_game (
        p_game_id OUT NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        v_player_id := required_player_id;

        BEGIN
            SELECT game_id
            INTO p_game_id
            FROM durak_active_session
            WHERE player_id = v_player_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_game_id := NULL;
        END;

        IF p_game_id IS NULL THEN
            success('у пользователя нет активной партии.', p_message);
        ELSE
            success('текущая GAME_ID=' || p_game_id || '.', p_message);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            p_game_id := NULL;
            record_failure(NULL, v_player_id, 'CURRENT_GAME', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END current_game;

    PROCEDURE create_game (
        p_game_id                OUT NUMBER,
        p_message                OUT VARCHAR2,
        p_deck_size              IN NUMBER DEFAULT 36,
        p_game_variant           IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode        IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs              IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec       IN NUMBER DEFAULT 60,
        p_idle_timeout_min       IN NUMBER DEFAULT 30,
        p_seed_text              IN VARCHAR2 DEFAULT NULL
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;

        durak_engine.create_game(
            p_creator_player_id      => v_player_id,
            p_deck_size              => p_deck_size,
            p_game_variant           => p_game_variant,
            p_first_move_mode        => p_first_move_mode,
            p_max_pairs              => p_max_pairs,
            p_turn_timeout_sec       => p_turn_timeout_sec,
            p_idle_timeout_min       => p_idle_timeout_min,
            p_seed_text              => p_seed_text,
            p_game_id                => p_game_id
        );

        COMMIT;
        success('создана партия GAME_ID=' || p_game_id || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'CREATE_GAME', v_code, v_error, p_message);
            p_game_id := NULL;
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END create_game;

    PROCEDURE create_daily_game (
        p_game_id                OUT NUMBER,
        p_daily_id               OUT NUMBER,
        p_message                OUT VARCHAR2,
        p_daily_date             IN DATE DEFAULT NULL,
        p_deck_size              IN NUMBER DEFAULT 36,
        p_game_variant           IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode        IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs              IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec       IN NUMBER DEFAULT 60,
        p_idle_timeout_min       IN NUMBER DEFAULT 30,
        p_rules_version          IN VARCHAR2 DEFAULT 'RULES-V1'
    ) IS
        v_player_id NUMBER;
        v_seed_text VARCHAR2(128);
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;

        p_daily_id := ensure_daily(
            p_daily_date      => p_daily_date,
            p_deck_size       => p_deck_size,
            p_game_variant    => p_game_variant,
            p_first_move_mode => p_first_move_mode,
            p_rules_version   => p_rules_version,
            p_seed_text       => v_seed_text
        );

        durak_engine.create_game(
            p_creator_player_id      => v_player_id,
            p_deck_size              => p_deck_size,
            p_game_variant           => p_game_variant,
            p_first_move_mode        => p_first_move_mode,
            p_max_pairs              => p_max_pairs,
            p_turn_timeout_sec       => p_turn_timeout_sec,
            p_idle_timeout_min       => p_idle_timeout_min,
            p_seed_text              => v_seed_text,
            p_daily_id               => p_daily_id,
            p_game_id                => p_game_id
        );

        COMMIT;
        success(
            'создана Daily-партия GAME_ID=' || p_game_id
            || ', DAILY_ID=' || p_daily_id || '.',
            p_message
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(
                p_game_id,
                v_player_id,
                'CREATE_DAILY_GAME',
                v_code,
                v_error,
                p_message
            );
            p_game_id := NULL;
            p_daily_id := NULL;
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END create_daily_game;

    PROCEDURE join_game (
        p_game_id IN NUMBER,
        p_seat_no OUT NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.join_game(v_player_id, p_game_id, p_seat_no);
        COMMIT;
        success('игрок присоединился к партии на место ' || p_seat_no || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            p_seat_no := NULL;
            record_failure(p_game_id, v_player_id, 'JOIN_GAME', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END join_game;

    PROCEDURE start_game (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.start_game(v_player_id, p_game_id);
        COMMIT;
        success('партия запущена.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'START_GAME', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END start_game;

    PROCEDURE attack (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.attack(v_player_id, p_game_id, p_card_code);
        COMMIT;
        success('атака принята: ' || UPPER(TRIM(p_card_code)) || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'ATTACK', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END attack;

    PROCEDURE defend (
        p_game_id           IN NUMBER,
        p_defense_card_code IN VARCHAR2,
        p_message           OUT VARCHAR2,
        p_pair_no           IN NUMBER DEFAULT NULL
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.defend(
            v_player_id,
            p_game_id,
            p_defense_card_code,
            p_pair_no
        );
        COMMIT;
        success('защита принята: ' || UPPER(TRIM(p_defense_card_code)) || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'DEFEND', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END defend;

    PROCEDURE throw_in (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.throw_in(v_player_id, p_game_id, p_card_code);
        COMMIT;
        success('подбрасывание принято: ' || UPPER(TRIM(p_card_code)) || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'THROW_IN', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END throw_in;

    PROCEDURE pass_throw (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.pass_throw(v_player_id, p_game_id);
        COMMIT;
        success('пас принят.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'PASS', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END pass_throw;

    PROCEDURE take_cards (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.take_cards(v_player_id, p_game_id);
        COMMIT;
        success('взятие карт принято.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'TAKE', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END take_cards;

    PROCEDURE transfer_attack (
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2,
        p_message   OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.transfer_attack(v_player_id, p_game_id, p_card_code);
        COMMIT;
        success('перевод принят: ' || UPPER(TRIM(p_card_code)) || '.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'TRANSFER', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END transfer_attack;

    PROCEDURE heartbeat (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.heartbeat(v_player_id, p_game_id);
        COMMIT;
        success('активность подтверждена.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'HEARTBEAT', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END heartbeat;

    PROCEDURE cancel_game (
        p_game_id IN NUMBER,
        p_message OUT VARCHAR2
    ) IS
        v_player_id NUMBER;
        v_code      NUMBER;
        v_error     VARCHAR2(1000);
    BEGIN
        SAVEPOINT durak_api_call;
        v_player_id := required_player_id;
        durak_engine.cancel_game(v_player_id, p_game_id);
        COMMIT;
        success('партия отменена.', p_message);
    EXCEPTION
        WHEN OTHERS THEN
            v_code := SQLCODE;
            v_error := SQLERRM;
            ROLLBACK TO durak_api_call;
            record_failure(p_game_id, v_player_id, 'CANCEL_GAME', v_code, v_error, p_message);
            IF NOT is_business_error(v_code) THEN
                RAISE;
            END IF;
    END cancel_game;

END durak_api;
/

SHOW ERRORS PACKAGE durak_api
SHOW ERRORS PACKAGE BODY durak_api
