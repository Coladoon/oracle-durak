PROMPT Создание человеко-понятного интерфейса DURAK_CONSOLE

CREATE OR REPLACE PACKAGE durak_console AUTHID DEFINER AS
    PROCEDURE play (
        p_command IN VARCHAR2,
        p_message OUT VARCHAR2
    );

    PROCEDURE play (
        p_game_id IN NUMBER,
        p_command IN VARCHAR2,
        p_message OUT VARCHAR2
    );

    PROCEDURE help (
        p_message OUT VARCHAR2
    );

END durak_console;
/

CREATE OR REPLACE PACKAGE BODY durak_console AS
    FUNCTION session_username RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
    END session_username;

    PROCEDURE print_message (
        p_text    IN VARCHAR2,
        p_message OUT VARCHAR2
    ) IS
    BEGIN
        p_message := SUBSTR(p_text, 1, 1000);
        DBMS_OUTPUT.PUT_LINE(p_message);
    END print_message;

    PROCEDURE help (
        p_message OUT VARCHAR2
    ) IS
    BEGIN
        print_message(
            'Команды: ХОД <карта>; БИТО <карта> [пара]; '
            || 'ПОДКИНУТЬ <карта>; ПЕРЕВОД <карта>; ВЗЯТЬ; ПАС. '
            || 'Можно отправить только код карты — действие определится по фазе.',
            p_message
        );
    END help;

    FUNCTION current_game_id RETURN NUMBER IS
        v_game_id  NUMBER;
        v_username VARCHAR2(128) := session_username;
    BEGIN
        SELECT active_session.game_id
        INTO v_game_id
        FROM durak_active_session active_session
        JOIN durak_player player_row
          ON player_row.player_id = active_session.player_id
        WHERE player_row.db_username = v_username;

        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20820,
                'У пользователя нет активной партии. Укажите GAME_ID явно.'
            );
    END current_game_id;

    FUNCTION token (
        p_command  IN VARCHAR2,
        p_position IN PLS_INTEGER
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN REGEXP_SUBSTR(p_command, '[^ ]+', 1, p_position);
    END token;

    FUNCTION is_card_code (
        p_value IN VARCHAR2
    ) RETURN BOOLEAN IS
    BEGIN
        RETURN REGEXP_LIKE(p_value, '^(10|[2-9JQKA])[CDHS]$');
    END is_card_code;

    PROCEDURE play (
        p_game_id IN NUMBER,
        p_command IN VARCHAR2,
        p_message OUT VARCHAR2
    ) IS
        v_command VARCHAR2(200) := UPPER(
            REGEXP_REPLACE(TRIM(REPLACE(p_command, CHR(9), ' ')), ' +', ' ')
        );
        v_action  VARCHAR2(30);
        v_card    VARCHAR2(3);
        v_pair    NUMBER;
        v_allowed VARCHAR2(30);
    BEGIN
        IF v_command IS NULL THEN
            print_message('ОТКАЗ: команда пуста. Выполните DURAK_CONSOLE.HELP.', p_message);
            RETURN;
        END IF;

        v_action := token(v_command, 1);

        IF v_action IN ('ПОМОЩЬ', 'HELP', '?') THEN
            help(p_message);
            RETURN;
        END IF;

        -- Короткая форма: DURAK_CONSOLE.PLAY('8H', :message).
        IF is_card_code(v_action) THEN
            v_card := v_action;
            BEGIN
                SELECT my_allowed_actions
                INTO v_allowed
                FROM v_game_status
                WHERE game_id = p_game_id
                  AND seat_no = viewer_seat_no;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    print_message('ОТКАЗ: партия не найдена или вы в ней не участвуете.', p_message);
                    RETURN;
            END;

            IF v_allowed = 'ATTACK' THEN
                durak_api.attack(p_game_id, v_card, p_message);
            ELSIF INSTR(v_allowed, 'DEFEND') > 0 THEN
                durak_api.defend(p_game_id, v_card, p_message, NULL);
            ELSIF INSTR(v_allowed, 'THROW_IN') > 0 THEN
                durak_api.throw_in(p_game_id, v_card, p_message);
            ELSE
                print_message(
                    'ОТКАЗ: сейчас карту положить нельзя. Разрешено: ' || v_allowed || '.',
                    p_message
                );
            END IF;
            RETURN;
        END IF;

        v_card := token(v_command, 2);

        IF v_action IN ('ХОД', 'АТАКА', 'ATTACK') THEN
            IF v_card IS NULL OR NOT is_card_code(v_card) THEN
                print_message('ОТКАЗ: укажите карту, например ХОД 8H.', p_message);
                RETURN;
            END IF;
            durak_api.attack(p_game_id, v_card, p_message);
        ELSIF v_action IN ('БИТО', 'БИТЬ', 'ЗАЩИТА', 'DEFEND') THEN
            IF v_card IS NULL OR NOT is_card_code(v_card) THEN
                print_message('ОТКАЗ: укажите карту, например БИТО 9H 1.', p_message);
                RETURN;
            END IF;
            BEGIN
                v_pair := TO_NUMBER(token(v_command, 3));
            EXCEPTION
                WHEN VALUE_ERROR THEN
                    print_message('ОТКАЗ: номер пары должен быть числом.', p_message);
                    RETURN;
            END;
            durak_api.defend(p_game_id, v_card, p_message, v_pair);
        ELSIF v_action IN ('ПОДКИНУТЬ', 'ПОДКИНЬ', 'ПОДБРОС', 'THROW') THEN
            IF v_card IS NULL OR NOT is_card_code(v_card) THEN
                print_message('ОТКАЗ: укажите карту, например ПОДКИНУТЬ 8C.', p_message);
                RETURN;
            END IF;
            durak_api.throw_in(p_game_id, v_card, p_message);
        ELSIF v_action IN ('ПЕРЕВОД', 'ПЕРЕВЕСТИ', 'TRANSFER') THEN
            IF v_card IS NULL OR NOT is_card_code(v_card) THEN
                print_message('ОТКАЗ: укажите карту, например ПЕРЕВОД 8D.', p_message);
                RETURN;
            END IF;
            durak_api.transfer_attack(p_game_id, v_card, p_message);
        ELSIF v_action IN ('ВЗЯТЬ', 'БЕРУ', 'TAKE') THEN
            durak_api.take_cards(p_game_id, p_message);
        ELSIF v_action IN ('ПАС', 'PASS') THEN
            durak_api.pass_throw(p_game_id, p_message);
        ELSE
            print_message(
                'ОТКАЗ: неизвестная команда «' || SUBSTR(v_action, 1, 30)
                || '». Выполните DURAK_CONSOLE.HELP.',
                p_message
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            print_message(
                'ОТКАЗ: ' || REGEXP_REPLACE(SQLERRM, '^ORA-[0-9]+: *', ''),
                p_message
            );
    END play;

    PROCEDURE play (
        p_command IN VARCHAR2,
        p_message OUT VARCHAR2
    ) IS
    BEGIN
        play(current_game_id, p_command, p_message);
    EXCEPTION
        WHEN OTHERS THEN
            print_message(
                'ОТКАЗ: ' || REGEXP_REPLACE(SQLERRM, '^ORA-[0-9]+: *', ''),
                p_message
            );
    END play;

END durak_console;
/

SHOW ERRORS PACKAGE durak_console
SHOW ERRORS PACKAGE BODY durak_console
