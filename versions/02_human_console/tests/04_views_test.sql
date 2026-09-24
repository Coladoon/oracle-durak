PROMPT Проверка маскирования представлений

DECLARE
    v_me_id          NUMBER;
    v_other_id       NUMBER;
    v_game_id        NUMBER;
    v_own_card_id    NUMBER;
    v_other_card_id  NUMBER;
    v_trump_card_id  NUMBER;
    v_private_own_id NUMBER;
    v_error_own_id   NUMBER;
    v_value          NUMBER;
    v_text           VARCHAR2(100);
    v_console_text   VARCHAR2(1000);
BEGIN
    SAVEPOINT before_view_test;

    SELECT MAX(player_id)
    INTO v_me_id
    FROM durak_player
    WHERE db_username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));

    IF v_me_id IS NULL THEN
        v_me_id := durak_id_seq.NEXTVAL;
        INSERT INTO durak_player (
            player_id, db_username, display_name, player_type
        ) VALUES (
            v_me_id,
            UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')),
            'Тестовый владелец',
            'HUMAN'
        );
    END IF;

    v_other_id := durak_id_seq.NEXTVAL;
    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_other_id, 'Тестовый соперник', 'BOT', 'EASY'
    );

    SELECT card_id INTO v_own_card_id
    FROM durak_card WHERE card_code = '6C';

    SELECT card_id INTO v_other_card_id
    FROM durak_card WHERE card_code = '7D';

    SELECT card_id INTO v_trump_card_id
    FROM durak_card WHERE card_code = 'AS';

    v_game_id := durak_id_seq.NEXTVAL;
    INSERT INTO durak_game (
        game_id,
        created_by_player_id,
        deck_size,
        game_variant,
        first_move_mode,
        max_pairs,
        seed_text,
        seed_hash,
        game_status,
        phase,
        trump_suit,
        trump_card_id,
        current_round_no,
        attacker_seat_no,
        defender_seat_no,
        current_actor_seat_no,
        started_at
    ) VALUES (
        v_game_id,
        v_me_id,
        36,
        'PODKIDNOY',
        'LOWEST_TRUMP',
        6,
        'view-test-seed',
        durak_random.game_seed_hash('view-test-seed', 36, 'PODKIDNOY'),
        'ACTIVE',
        'WAIT_ATTACK',
        'S',
        v_trump_card_id,
        1,
        1,
        2,
        1,
        SYSTIMESTAMP
    );

    INSERT INTO durak_game_player (
        game_id, seat_no, player_id, player_status, is_creator, hand_count
    ) VALUES (
        v_game_id, 1, v_me_id, 'ACTIVE', 'Y', 1
    );

    INSERT INTO durak_game_player (
        game_id, seat_no, player_id, player_status, is_creator, hand_count
    ) VALUES (
        v_game_id, 2, v_other_id, 'ACTIVE', 'N', 1
    );

    INSERT INTO durak_game_card (
        game_id, card_id, deck_pos, card_zone, owner_seat_no,
        received_seq, is_face_up
    ) VALUES (
        v_game_id, v_own_card_id, 1, 'HAND', 1, 1, 'N'
    );

    INSERT INTO durak_game_card (
        game_id, card_id, deck_pos, card_zone, owner_seat_no,
        received_seq, is_face_up
    ) VALUES (
        v_game_id, v_other_card_id, 2, 'HAND', 2, 2, 'N'
    );

    INSERT INTO durak_game_card (
        game_id, card_id, deck_pos, card_zone, is_face_up
    ) VALUES (
        v_game_id, v_trump_card_id, 3, 'TALON', 'Y'
    );

    INSERT INTO durak_event (
        event_id, game_id, event_no, event_type, event_source,
        actor_player_id, actor_seat_no, card_id, visibility_code,
        event_message
    ) VALUES (
        durak_id_seq.NEXTVAL, v_game_id, 1, 'ATTACK', 'MANUAL',
        v_me_id, 1, v_own_card_id, 'PUBLIC', 'Открытое тестовое действие'
    );

    INSERT INTO durak_event (
        event_id, game_id, event_no, event_type, event_source,
        actor_player_id, actor_seat_no, card_id, visibility_code,
        visible_to_seat_no, event_message
    ) VALUES (
        durak_id_seq.NEXTVAL, v_game_id, 2, 'DRAW', 'SYSTEM',
        v_other_id, 2, v_other_card_id, 'PRIVATE',
        2, 'Чужое закрытое действие'
    );

    v_private_own_id := durak_id_seq.NEXTVAL;
    INSERT INTO durak_event (
        event_id, game_id, event_no, event_type, event_source,
        actor_player_id, actor_seat_no, card_id, visibility_code,
        visible_to_seat_no, event_message
    ) VALUES (
        v_private_own_id, v_game_id, 3, 'DRAW', 'SYSTEM',
        v_me_id, 1, v_own_card_id, 'PRIVATE',
        1, 'Своё закрытое действие'
    );

    SELECT COUNT(*), MAX(card_code)
    INTO v_value, v_text
    FROM v_hand_mine
    WHERE game_id = v_game_id;
    durak_test.assert_number('V_HAND_MINE показывает одну свою карту', 1, v_value);
    durak_test.assert_text('V_HAND_MINE показывает код своей карты', '6C', v_text);

    SELECT COUNT(*)
    INTO v_value
    FROM v_hand_public
    WHERE game_id = v_game_id;
    durak_test.assert_number('V_HAND_PUBLIC показывает обоих участников', 2, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_game_status
    WHERE game_id = v_game_id;
    durak_test.assert_number('V_GAME_STATUS содержит строки обоих игроков', 2, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_table
    WHERE game_id = v_game_id
      AND allowed_actions = 'ATTACK';
    durak_test.assert_number('V_TABLE сообщает допустимую первую атаку', 1, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_log
    WHERE game_id = v_game_id;
    durak_test.assert_number('V_LOG скрывает чужое закрытое событие', 2, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_game_console
    WHERE game_id = v_game_id
      AND INSTR(hand_text, '6C') > 0
      AND INSTR(turn_text, 'ВАШ ХОД') > 0;
    durak_test.assert_number(
        'V_GAME_CONSOLE показывает понятное состояние и свою руку',
        1,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_log_text
    WHERE game_id = v_game_id
      AND event_no = 1
      AND INSTR(log_line, 'атакует 6C') > 0;
    durak_test.assert_number('V_LOG_TEXT формирует понятную строку события', 1, v_value);

    durak_console.help(v_console_text);
    durak_test.assert_number(
        'DURAK_CONSOLE показывает справку по русским командам',
        1,
        CASE WHEN INSTR(v_console_text, 'ХОД <карта>') > 0 THEN 1 ELSE 0 END
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_log
    WHERE game_id = v_game_id
      AND event_no = 2;
    durak_test.assert_number('Чужой приватный добор не виден', 0, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_replay
    WHERE game_id = v_game_id;
    durak_test.assert_number(
        'Активный реплей скрывает чужое закрытое событие',
        2,
        v_value
    );

    UPDATE durak_game
    SET game_status = 'FINISHED',
        phase = 'FINISHED',
        current_actor_seat_no = NULL,
        finished_at = SYSTIMESTAMP
    WHERE game_id = v_game_id;

    INSERT INTO durak_round (
        game_id, round_no, round_status,
        primary_attacker_seat_no, initial_defender_seat_no,
        defender_seat_no, defender_hand_at_start, attack_limit,
        ended_at
    ) VALUES (
        v_game_id, 1, 'DEFENDED', 1, 2, 2, 1, 1, SYSTIMESTAMP
    );

    INSERT INTO durak_round (
        game_id, round_no, round_status,
        primary_attacker_seat_no, initial_defender_seat_no,
        defender_seat_no, defender_hand_at_start, attack_limit,
        ended_at
    ) VALUES (
        v_game_id, 2, 'TAKEN', 1, 2, 2, 1, 1, SYSTIMESTAMP
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_replay
    WHERE game_id = v_game_id;
    durak_test.assert_number(
        'После завершения участнику доступен полный реплей',
        3,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_analytics
    WHERE game_id = v_game_id
      AND events_count = 3
      AND actions_count = 1;
    durak_test.assert_number(
        'V_ANALYTICS считает события и игровые действия отдельно',
        1,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_analytics
    WHERE game_id = v_game_id
      AND rounds_count = 2
      AND defended_rounds_count = 1
      AND taken_rounds_count = 1
      AND take_share = 0.5;
    durak_test.assert_number(
        'V_ANALYTICS различает отбой и взятие',
        1,
        v_value
    );

    v_error_own_id := durak_id_seq.NEXTVAL;
    INSERT INTO durak_error (
        error_id, game_id, player_id, db_username,
        action_type, error_code, error_message
    ) VALUES (
        v_error_own_id,
        v_game_id,
        v_me_id,
        UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')),
        'TEST',
        -20000,
        'Свой тестовый отказ'
    );

    INSERT INTO durak_error (
        error_id, game_id, player_id, db_username,
        action_type, error_code, error_message
    ) VALUES (
        durak_id_seq.NEXTVAL,
        v_game_id,
        v_other_id,
        'SOME_OTHER_USER',
        'TEST',
        -20001,
        'Чужой тестовый отказ'
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_errors
    WHERE game_id = v_game_id;
    durak_test.assert_number('V_ERRORS показывает только свой отказ', 1, v_value);

    ROLLBACK TO before_view_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_view_test;
        RAISE;
END;
/
