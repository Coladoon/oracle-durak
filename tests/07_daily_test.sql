PROMPT Проверка Daily-раскладки и табло дня

DECLARE
    v_creator        NUMBER;
    v_second         NUMBER;
    v_daily_id       NUMBER;
    v_daily_game     NUMBER;
    v_attacker_seat  NUMBER;
    v_defender_seat  NUMBER;
    v_attacker_id    NUMBER;
    v_defender_id    NUMBER;
    v_seat_no        NUMBER;
    v_seed_text      VARCHAR2(128);
    v_rules_version  VARCHAR2(20);
    v_value          NUMBER;
BEGIN
    SAVEPOINT before_daily_test;

    v_creator := durak_id_seq.NEXTVAL;
    v_second := durak_id_seq.NEXTVAL;

    -- Служебные игроки не резервируют пользовательские сессии и нужны только
    -- для изолированного теста движка.
    INSERT INTO durak_player (
        player_id, display_name, player_type
    ) VALUES (
        v_creator, 'Daily Test Creator', 'SYSTEM'
    );

    INSERT INTO durak_player (
        player_id, display_name, player_type
    ) VALUES (
        v_second, 'Daily Test Second', 'SYSTEM'
    );

    v_daily_id := durak_id_seq.NEXTVAL;
    v_rules_version := SUBSTR('T' || TO_CHAR(v_daily_id), 1, 20);
    v_seed_text := durak_random.daily_seed(
        DATE '2099-12-31',
        36,
        'PODKIDNOY',
        'LOWEST_TRUMP',
        v_rules_version
    );

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
        DATE '2099-12-31',
        36,
        'PODKIDNOY',
        'LOWEST_TRUMP',
        v_seed_text,
        durak_random.hash_text(v_seed_text),
        v_rules_version
    );

    durak_engine.create_game(
        p_creator_player_id => v_creator,
        p_deck_size => 36,
        p_game_variant => 'PODKIDNOY',
        p_first_move_mode => 'LOWEST_TRUMP',
        p_daily_id => v_daily_id,
        p_game_id => v_daily_game
    );
    durak_engine.join_game(v_second, v_daily_game, v_seat_no);
    durak_engine.start_game(v_creator, v_daily_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_game
    WHERE game_id = v_daily_game
      AND daily_id = v_daily_id
      AND seed_text = v_seed_text;
    durak_test.assert_number(
        'Daily-конфигурация определяет seed партии',
        1,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_daily
    WHERE daily_id = v_daily_id
      AND daily_date = DATE '2099-12-31';
    durak_test.assert_number('V_DAILY показывает раскладку дня', 1, v_value);

    SELECT attacker_seat_no, defender_seat_no
    INTO v_attacker_seat, v_defender_seat
    FROM durak_game
    WHERE game_id = v_daily_game;

    SELECT player_id
    INTO v_attacker_id
    FROM durak_game_player
    WHERE game_id = v_daily_game
      AND seat_no = v_attacker_seat;

    SELECT player_id
    INTO v_defender_id
    FROM durak_game_player
    WHERE game_id = v_daily_game
      AND seat_no = v_defender_seat;

    -- Сводим тестовую партию к последней гарантированно бьющейся паре.
    UPDATE durak_game_card
    SET card_zone = 'DISCARD',
        owner_seat_no = NULL,
        table_pair_no = NULL,
        received_seq = NULL,
        is_face_up = 'Y'
    WHERE game_id = v_daily_game;

    UPDATE durak_game_card
    SET card_zone = 'HAND',
        owner_seat_no = v_attacker_seat,
        received_seq = 1,
        is_face_up = 'N'
    WHERE game_id = v_daily_game
      AND card_id = (SELECT card_id FROM durak_card WHERE card_code = '6C');

    UPDATE durak_game_card
    SET card_zone = 'HAND',
        owner_seat_no = v_defender_seat,
        received_seq = 1,
        is_face_up = 'N'
    WHERE game_id = v_daily_game
      AND card_id = (SELECT card_id FROM durak_card WHERE card_code = '7C');

    UPDATE durak_game_player
    SET hand_count = CASE
        WHEN seat_no = v_attacker_seat THEN 1
        WHEN seat_no = v_defender_seat THEN 2
        ELSE 0
    END
    WHERE game_id = v_daily_game;

    UPDATE durak_game_card
    SET card_zone = 'HAND',
        owner_seat_no = v_defender_seat,
        received_seq = 2,
        is_face_up = 'N'
    WHERE game_id = v_daily_game
      AND card_id = (SELECT card_id FROM durak_card WHERE card_code = '8D');

    durak_engine.attack(v_attacker_id, v_daily_game, '6C');
    durak_engine.defend(v_defender_id, v_daily_game, '7C', 1);
    durak_engine.pass_throw(v_attacker_id, v_daily_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_daily_result
    WHERE daily_id = v_daily_id
      AND game_id = v_daily_game
      AND result_code IN ('WIN', 'LOSS');
    durak_test.assert_number(
        'Завершение Daily записывает победу и поражение',
        2,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_daily_results
    WHERE daily_id = v_daily_id
      AND game_id = v_daily_game
      AND daily_place IN (1, 2);
    durak_test.assert_number(
        'V_DAILY_RESULTS строит табло завершённой партии',
        2,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_leaderboard
    WHERE player_id IN (v_creator, v_second)
      AND games_played = 1
      AND avg_duration_sec IS NOT NULL
      AND avg_rounds = 1
      AND ((wins = 1 AND losses = 0) OR (wins = 0 AND losses = 1));
    durak_test.assert_number(
        'V_LEADERBOARD считает победу, поражение и длительность',
        2,
        v_value
    );

    ROLLBACK TO before_daily_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_daily_test;
        RAISE;
END;
/
