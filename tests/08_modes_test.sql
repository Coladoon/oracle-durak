PROMPT Проверка режимов 2–6 игроков, колоды 52, перевода и подбрасывания

DECLARE
    TYPE number_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_player          number_list;
    v_game52_a        NUMBER;
    v_game52_b        NUMBER;
    v_full_game       NUMBER;
    v_throw_game      NUMBER;
    v_seat_no         NUMBER;
    v_attacker_seat   NUMBER;
    v_defender_seat   NUMBER;
    v_new_defender    NUMBER;
    v_attacker_id     NUMBER;
    v_defender_id     NUMBER;
    v_order_a         VARCHAR2(4000);
    v_order_b         VARCHAR2(4000);
    v_value           NUMBER;

    PROCEDURE put_card_into_hand (
        p_game_id       IN NUMBER,
        p_card_code     IN VARCHAR2,
        p_target_seat   IN NUMBER,
        p_excluded_codes IN VARCHAR2
    ) IS
        v_card_id        NUMBER;
        v_replacement_id NUMBER;
        v_zone1          VARCHAR2(10);
        v_owner1         NUMBER;
        v_pair1          NUMBER;
        v_received1      NUMBER;
        v_face1          CHAR(1);
        v_zone2          VARCHAR2(10);
        v_owner2         NUMBER;
        v_pair2          NUMBER;
        v_received2      NUMBER;
        v_face2          CHAR(1);
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
              AND INSTR(
                    ',' || p_excluded_codes || ',',
                    ',' || c.card_code || ','
                  ) = 0
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
    SAVEPOINT before_modes_test;

    FOR i IN 1 .. 7 LOOP
        v_player(i) := durak_id_seq.NEXTVAL;
        INSERT INTO durak_player (
            player_id, display_name, player_type
        ) VALUES (
            v_player(i), 'Modes Test ' || i, 'SYSTEM'
        );
    END LOOP;

    -- Проверяем верхнюю границу в шесть участников и отказ седьмому.
    durak_engine.create_game(
        p_creator_player_id => v_player(1),
        p_seed_text => 'six-player-lobby',
        p_game_id => v_full_game
    );
    FOR i IN 2 .. 6 LOOP
        durak_engine.join_game(v_player(i), v_full_game, v_seat_no);
    END LOOP;

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_player
    WHERE game_id = v_full_game;
    durak_test.assert_number('К партии подключаются шесть игроков', 6, v_value);

    BEGIN
        durak_engine.join_game(v_player(7), v_full_game, v_seat_no);
        durak_test.fail('Седьмой игрок отклоняется', 'седьмой игрок был добавлен');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20715 THEN
                durak_test.pass('Седьмой игрок отклоняется');
            ELSE
                durak_test.fail(
                    'Седьмой игрок отклоняется',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;

    -- Две одинаковые партии подтверждают режим 52/PEREVODNOY и seed-first.
    durak_engine.create_game(
        p_creator_player_id => v_player(1),
        p_deck_size => 52,
        p_game_variant => 'PEREVODNOY',
        p_first_move_mode => 'SEEDED_RANDOM',
        p_seed_text => 'good-grade-modes',
        p_game_id => v_game52_a
    );
    FOR i IN 2 .. 6 LOOP
        durak_engine.join_game(v_player(i), v_game52_a, v_seat_no);
    END LOOP;
    durak_engine.start_game(v_player(1), v_game52_a);

    durak_engine.create_game(
        p_creator_player_id => v_player(1),
        p_deck_size => 52,
        p_game_variant => 'PEREVODNOY',
        p_first_move_mode => 'SEEDED_RANDOM',
        p_seed_text => 'good-grade-modes',
        p_game_id => v_game52_b
    );
    FOR i IN 2 .. 6 LOOP
        durak_engine.join_game(v_player(i), v_game52_b, v_seat_no);
    END LOOP;
    durak_engine.start_game(v_player(1), v_game52_b);

    SELECT LISTAGG(c.card_code, ',') WITHIN GROUP (ORDER BY gc.deck_pos)
    INTO v_order_a
    FROM durak_game_card gc
    JOIN durak_card c ON c.card_id = gc.card_id
    WHERE gc.game_id = v_game52_a;

    SELECT LISTAGG(c.card_code, ',') WITHIN GROUP (ORDER BY gc.deck_pos)
    INTO v_order_b
    FROM durak_game_card gc
    JOIN durak_card c ON c.card_id = gc.card_id
    WHERE gc.game_id = v_game52_b;

    durak_test.assert_text(
        'Колода 52 повторяется при одинаковом seed',
        v_order_a,
        v_order_b
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game g
    WHERE g.game_id = v_game52_a
      AND g.deck_size = 52
      AND g.game_variant = 'PEREVODNOY'
      AND g.first_move_mode = 'SEEDED_RANDOM'
      AND g.max_pairs = 8
      AND g.attacker_seat_no = (
          SELECT attacker_seat_no
          FROM durak_game
          WHERE game_id = v_game52_b
      );
    durak_test.assert_number(
        'Параметры 52/переводной/случайный по seed применены',
        1,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game_card
    WHERE game_id = v_game52_a
      AND card_zone = 'TALON';
    durak_test.assert_number(
        'После раздачи шести игрокам в колоде 52 остаётся 16 карт',
        16,
        v_value
    );

    -- Проверяем перевод первой атаки на следующего активного игрока.
    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_game52_a;

    v_new_defender := durak_rules.next_active_seat(v_game52_a, v_defender_seat);

    SELECT player_id INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_game52_a AND seat_no = v_attacker_seat;

    SELECT player_id INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_game52_a AND seat_no = v_defender_seat;

    put_card_into_hand(v_game52_a, '6C', v_attacker_seat, '6C,6D');
    put_card_into_hand(v_game52_a, '6D', v_defender_seat, '6C,6D');
    durak_engine.attack(v_attacker_id, v_game52_a, '6C');
    durak_engine.transfer_attack(v_defender_id, v_game52_a, '6D');

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game g
    WHERE g.game_id = v_game52_a
      AND g.defender_seat_no = v_new_defender
      AND g.current_actor_seat_no = v_new_defender
      AND (
          SELECT COUNT(*)
          FROM durak_table_pair tp
          WHERE tp.game_id = g.game_id
            AND tp.round_no = g.current_round_no
      ) = 2;
    durak_test.assert_number(
        'Перевод добавляет карту и меняет защитника',
        1,
        v_value
    );

    -- Вышедший игрок пропускается при обходе по часовой стрелке.
    UPDATE durak_game_player
    SET player_status = 'OUT'
    WHERE game_id = v_game52_a
      AND seat_no = 2;

    durak_test.assert_number(
        'Вышедший игрок пропускается',
        3,
        durak_rules.next_active_seat(v_game52_a, 1)
    );

    -- Подкидной режим: разрешён тот же ранг, другой ранг отклоняется.
    durak_engine.create_game(
        p_creator_player_id => v_player(1),
        p_deck_size => 36,
        p_game_variant => 'PODKIDNOY',
        p_first_move_mode => 'LOWEST_TRUMP',
        p_seed_text => 'throw-in-rank-test',
        p_game_id => v_throw_game
    );
    durak_engine.join_game(v_player(2), v_throw_game, v_seat_no);
    durak_engine.start_game(v_player(1), v_throw_game);

    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_throw_game;

    SELECT player_id INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_throw_game AND seat_no = v_attacker_seat;

    SELECT player_id INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_throw_game AND seat_no = v_defender_seat;

    put_card_into_hand(v_throw_game, '8C', v_attacker_seat, '8C,8D,7S,9C');
    put_card_into_hand(v_throw_game, '8D', v_attacker_seat, '8C,8D,7S,9C');
    put_card_into_hand(v_throw_game, '7S', v_attacker_seat, '8C,8D,7S,9C');
    put_card_into_hand(v_throw_game, '9C', v_defender_seat, '8C,8D,7S,9C');

    durak_engine.attack(v_attacker_id, v_throw_game, '8C');
    durak_engine.defend(v_defender_id, v_throw_game, '9C', 1);

    BEGIN
        durak_engine.throw_in(v_attacker_id, v_throw_game, '7S');
        durak_test.fail(
            'Подброс другого достоинства отклоняется',
            'карта другого достоинства принята'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20742 THEN
                durak_test.pass('Подброс другого достоинства отклоняется');
            ELSE
                durak_test.fail(
                    'Подброс другого достоинства отклоняется',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;

    durak_engine.throw_in(v_attacker_id, v_throw_game, '8D');

    SELECT COUNT(*)
    INTO v_value
    FROM durak_table_pair
    WHERE game_id = v_throw_game
      AND round_no = 1;
    durak_test.assert_number(
        'Подброс того же достоинства создаёт вторую пару',
        2,
        v_value
    );

    ROLLBACK TO before_modes_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_modes_test;
        RAISE;
END;
/
