PROMPT Проверка игрового автомата и полного раунда

DECLARE
    v_player1        NUMBER;
    v_player2        NUMBER;
    v_human_player   NUMBER;
    v_game1          NUMBER;
    v_game2          NUMBER;
    v_extra_game     NUMBER;
    v_timeout_game   NUMBER;
    v_idle_game      NUMBER;
    v_unlimited_game NUMBER;
    v_attacker_id    NUMBER;
    v_defender_id    NUMBER;
    v_attacker_seat  NUMBER;
    v_defender_seat  NUMBER;
    v_card_code      VARCHAR2(3);
    v_order1         VARCHAR2(4000);
    v_order2         VARCHAR2(4000);
    v_phase_text     VARCHAR2(50);
    v_deadline_before TIMESTAMP WITH TIME ZONE;
    v_value          NUMBER;

    PROCEDURE put_card_into_hand (
        p_game_id      IN NUMBER,
        p_card_code    IN VARCHAR2,
        p_target_seat  IN NUMBER,
        p_excluded_code IN VARCHAR2
    ) IS
        v_card_id          NUMBER;
        v_replacement_id   NUMBER;
        v_zone1            VARCHAR2(10);
        v_owner1           NUMBER;
        v_pair1            NUMBER;
        v_received1        NUMBER;
        v_face1            CHAR(1);
        v_zone2            VARCHAR2(10);
        v_owner2           NUMBER;
        v_pair2            NUMBER;
        v_received2        NUMBER;
        v_face2            CHAR(1);
    BEGIN
        SELECT gc.card_id, gc.card_zone, gc.owner_seat_no,
               gc.table_pair_no, gc.received_seq, gc.is_face_up
        INTO v_card_id, v_zone1, v_owner1,
             v_pair1, v_received1, v_face1
        FROM durak_game_card gc
        JOIN durak_card c ON c.card_id = gc.card_id
        WHERE gc.game_id = p_game_id
          AND c.card_code = p_card_code;

        IF v_zone1 = 'HAND' AND v_owner1 = p_target_seat THEN
            RETURN;
        END IF;

        SELECT card_id, card_zone, owner_seat_no,
               table_pair_no, received_seq, is_face_up
        INTO v_replacement_id, v_zone2, v_owner2,
             v_pair2, v_received2, v_face2
        FROM (
            SELECT gc.card_id, gc.card_zone, gc.owner_seat_no,
                   gc.table_pair_no, gc.received_seq, gc.is_face_up
            FROM durak_game_card gc
            JOIN durak_card c ON c.card_id = gc.card_id
            WHERE gc.game_id = p_game_id
              AND gc.card_zone = 'HAND'
              AND gc.owner_seat_no = p_target_seat
              AND gc.card_id <> v_card_id
              AND c.card_code <> p_excluded_code
            ORDER BY gc.received_seq, gc.card_id
        )
        WHERE ROWNUM = 1;

        UPDATE durak_game_card
        SET card_zone = 'DISCARD',
            owner_seat_no = NULL,
            table_pair_no = NULL,
            received_seq = NULL,
            is_face_up = 'Y'
        WHERE game_id = p_game_id
          AND card_id = v_card_id;

        UPDATE durak_game_card
        SET card_zone = v_zone1,
            owner_seat_no = v_owner1,
            table_pair_no = v_pair1,
            received_seq = v_received1,
            is_face_up = v_face1
        WHERE game_id = p_game_id
          AND card_id = v_replacement_id;

        UPDATE durak_game_card
        SET card_zone = v_zone2,
            owner_seat_no = v_owner2,
            table_pair_no = v_pair2,
            received_seq = v_received2,
            is_face_up = v_face2
        WHERE game_id = p_game_id
          AND card_id = v_card_id;
    END put_card_into_hand;
BEGIN
    SAVEPOINT before_engine_test;

    v_player1 := durak_id_seq.NEXTVAL;
    v_player2 := durak_id_seq.NEXTVAL;

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_player1, 'Engine Test 1', 'BOT', 'EASY'
    );

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_player2, 'Engine Test 2', 'BOT', 'EASY'
    );

    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_seed_text => 'engine-repeatable-seed',
        p_game_id => v_game1
    );
    durak_engine.join_game(v_player2, v_game1, v_value);
    durak_engine.start_game(v_player1, v_game1);

    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_seed_text => 'engine-repeatable-seed',
        p_game_id => v_game2
    );
    durak_engine.join_game(v_player2, v_game2, v_value);
    durak_engine.start_game(v_player1, v_game2);

    SELECT LISTAGG(c.card_code, ',') WITHIN GROUP (ORDER BY gc.deck_pos)
    INTO v_order1
    FROM durak_game_card gc
    JOIN durak_card c ON c.card_id = gc.card_id
    WHERE gc.game_id = v_game1;

    SELECT LISTAGG(c.card_code, ',') WITHIN GROUP (ORDER BY gc.deck_pos)
    INTO v_order2
    FROM durak_game_card gc
    JOIN durak_card c ON c.card_id = gc.card_id
    WHERE gc.game_id = v_game2;

    durak_test.assert_text(
        'Движок повторяет полный порядок колоды по seed',
        v_order1,
        v_order2
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game1;
    durak_test.assert_number('Движок создал 36 карт партии', 36, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game1
      AND card_zone = 'TALON';
    durak_test.assert_number('После раздачи двум игрокам в талоне 24 карты', 24, v_value);

    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_game1;

    SELECT player_id INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_game1 AND seat_no = v_attacker_seat;

    SELECT player_id INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_game1 AND seat_no = v_defender_seat;

    -- Принудительно формируем заведомо корректную пару покрытия,
    -- не меняя количество карт у игроков и в талоне.
    put_card_into_hand(v_game1, '6C', v_attacker_seat, '7C');
    put_card_into_hand(v_game1, '7C', v_defender_seat, '6C');

    durak_engine.attack(v_attacker_id, v_game1, '6C');

    SELECT phase_before || '>' || phase_after
    INTO v_phase_text
    FROM durak_event
    WHERE game_id = v_game1
      AND event_type = 'ATTACK'
      AND event_no = (
          SELECT MAX(event_no)
          FROM durak_event
          WHERE game_id = v_game1
            AND event_type = 'ATTACK'
      );
    durak_test.assert_text(
        'Реплей фиксирует переход после атаки',
        'WAIT_ATTACK>WAIT_DEFENSE',
        v_phase_text
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_table_pair
    WHERE game_id = v_game1
      AND round_no = 1
      AND pair_status = 'OPEN';
    durak_test.assert_number('Атака создаёт открытую пару', 1, v_value);

    durak_engine.defend(v_defender_id, v_game1, '7C', 1);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_table_pair
    WHERE game_id = v_game1
      AND round_no = 1
      AND pair_status = 'COVERED';
    durak_test.assert_number('Корректная защита покрывает пару', 1, v_value);

    durak_engine.pass_throw(v_attacker_id, v_game1);

    SELECT phase_after
    INTO v_phase_text
    FROM durak_event
    WHERE game_id = v_game1
      AND event_type = 'PASS'
      AND event_no = (
          SELECT MAX(event_no)
          FROM durak_event
          WHERE game_id = v_game1
            AND event_type = 'PASS'
      );
    durak_test.assert_text(
        'Реплей фиксирует состояние после завершения раунда',
        'WAIT_ATTACK',
        v_phase_text
    );

    SELECT current_round_no
    INTO v_value
    FROM durak_game
    WHERE game_id = v_game1;
    durak_test.assert_number('После паса начат второй раунд', 2, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game1
      AND card_zone = 'DISCARD';
    durak_test.assert_number('Две покрытые карты ушли в отбой', 2, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game1
      AND card_zone = 'TALON';
    durak_test.assert_number('После добора в талоне осталось 22 карты', 22, v_value);

    SELECT MIN(hand_count)
    INTO v_value
    FROM durak_game_player
    WHERE game_id = v_game1;
    durak_test.assert_number('После отбоя руки пополнены до шести', 6, v_value);

    -- Ослабление домашнего лимита действует только после закрытия талона.
    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_deck_size => 52,
        p_max_pairs => 8,
        p_limit_by_defender_hand => 'N',
        p_seed_text => 'unlimited-table-test',
        p_game_id => v_unlimited_game
    );
    durak_engine.join_game(v_player2, v_unlimited_game, v_value);
    durak_engine.start_game(v_player1, v_unlimited_game);

    SELECT attack_limit
    INTO v_value
    FROM durak_round
    WHERE game_id = v_unlimited_game
      AND round_no = 1;
    durak_test.assert_number(
        'До закрытия талона лимит всё равно ограничен рукой защитника',
        6,
        v_value
    );

    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_unlimited_game;

    SELECT player_id INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_unlimited_game AND seat_no = v_attacker_seat;

    SELECT player_id INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_unlimited_game AND seat_no = v_defender_seat;

    UPDATE durak_game_card
    SET card_zone = 'DISCARD',
        owner_seat_no = NULL,
        table_pair_no = NULL,
        received_seq = NULL,
        is_face_up = 'Y'
    WHERE game_id = v_unlimited_game
      AND card_zone = 'TALON';

    put_card_into_hand(v_unlimited_game, '6C', v_attacker_seat, '7C');
    put_card_into_hand(v_unlimited_game, '7C', v_defender_seat, '6C');
    durak_engine.attack(v_attacker_id, v_unlimited_game, '6C');
    durak_engine.defend(v_defender_id, v_unlimited_game, '7C', 1);
    durak_engine.pass_throw(v_attacker_id, v_unlimited_game);

    SELECT attack_limit
    INTO v_value
    FROM durak_round
    WHERE game_id = v_unlimited_game
      AND round_no = 2;
    durak_test.assert_number(
        'После закрытия талона домашнее правило разрешает max_pairs',
        8,
        v_value
    );

    -- Во второй партии проверяем ветку взятия.
    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_game2;

    SELECT player_id INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_game2 AND seat_no = v_attacker_seat;

    SELECT player_id INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_game2 AND seat_no = v_defender_seat;

    SELECT card_code
    INTO v_card_code
    FROM (
        SELECT c.card_code
        FROM durak_game_card gc
        JOIN durak_card c ON c.card_id = gc.card_id
        WHERE gc.game_id = v_game2
          AND gc.card_zone = 'HAND'
          AND gc.owner_seat_no = v_attacker_seat
        ORDER BY c.rank_value, c.suit_code
    )
    WHERE ROWNUM = 1;

    durak_engine.attack(v_attacker_id, v_game2, v_card_code);
    durak_engine.take_cards(v_defender_id, v_game2);

    SELECT current_round_no
    INTO v_value
    FROM durak_game
    WHERE game_id = v_game2;
    durak_test.assert_number('После взятия начат второй раунд', 2, v_value);

    SELECT hand_count
    INTO v_value
    FROM durak_game_player
    WHERE game_id = v_game2
      AND seat_no = v_defender_seat;
    durak_test.assert_number('Защитник получил атакующую карту', 7, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game2
      AND card_zone = 'TALON';
    durak_test.assert_number('После взятия первым добрал атакующий', 23, v_value);

    -- Проверяем автоматические действия по таймеру.
    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_seed_text => 'timeout-seed',
        p_turn_timeout_sec => 1,
        p_game_id => v_timeout_game
    );
    durak_engine.join_game(v_player2, v_timeout_game, v_value);
    durak_engine.start_game(v_player1, v_timeout_game);

    SELECT action_deadline_at
    INTO v_deadline_before
    FROM durak_game
    WHERE game_id = v_timeout_game;

    SELECT gp.player_id
    INTO v_defender_id
    FROM durak_game g
    JOIN durak_game_player gp
      ON gp.game_id = g.game_id
     AND gp.seat_no = g.defender_seat_no
    WHERE g.game_id = v_timeout_game;

    durak_engine.heartbeat(v_defender_id, v_timeout_game);

    SELECT CASE WHEN action_deadline_at = v_deadline_before THEN 1 ELSE 0 END
    INTO v_value
    FROM durak_game
    WHERE game_id = v_timeout_game;
    durak_test.assert_number(
        'Heartbeat ожидающего игрока не продлевает чужой ход',
        1,
        v_value
    );

    UPDATE durak_game
    SET action_deadline_at = SYSTIMESTAMP - NUMTODSINTERVAL(1, 'SECOND')
    WHERE game_id = v_timeout_game;

    durak_engine.process_timeout(v_timeout_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_event
    WHERE game_id = v_timeout_game
      AND event_type = 'ATTACK'
      AND event_source = 'TIMEOUT';
    durak_test.assert_number('Таймер автоматически делает первую атаку', 1, v_value);

    UPDATE durak_game
    SET action_deadline_at = SYSTIMESTAMP - NUMTODSINTERVAL(1, 'SECOND')
    WHERE game_id = v_timeout_game;

    durak_engine.process_timeout(v_timeout_game);

    SELECT current_round_no
    INTO v_value
    FROM durak_game
    WHERE game_id = v_timeout_game;
    durak_test.assert_number('Таймер защитника приводит к взятию', 2, v_value);

    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_seed_text => 'idle-seed',
        p_idle_timeout_min => 1,
        p_game_id => v_idle_game
    );

    UPDATE durak_game
    SET last_activity_at = SYSTIMESTAMP - NUMTODSINTERVAL(2, 'MINUTE')
    WHERE game_id = v_idle_game;

    durak_engine.expire_idle_game(v_idle_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game
    WHERE game_id = v_idle_game
      AND game_status = 'EXPIRED'
      AND phase = 'FINISHED';
    durak_test.assert_number('Простаивающая партия корректно завершена', 1, v_value);

    -- Отдельно проверяем запрет второй одновременной сессии человека.
    v_human_player := durak_id_seq.NEXTVAL;
    INSERT INTO durak_player (
        player_id, db_username, display_name, player_type
    ) VALUES (
        v_human_player,
        'ENGINE_TEST_USER_' || v_human_player,
        'Engine Human Test',
        'HUMAN'
    );

    durak_engine.create_game(
        p_creator_player_id => v_human_player,
        p_seed_text => 'one-session-1',
        p_game_id => v_extra_game
    );

    BEGIN
        durak_engine.create_game(
            p_creator_player_id => v_human_player,
            p_seed_text => 'one-session-2',
            p_game_id => v_extra_game
        );
        durak_test.fail(
            'Запрещена вторая активная сессия',
            'вторая партия была создана'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20706 THEN
                durak_test.pass('Запрещена вторая активная сессия');
            ELSE
                durak_test.fail(
                    'Запрещена вторая активная сессия',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;

    ROLLBACK TO before_engine_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_engine_test;
        RAISE;
END;
/
