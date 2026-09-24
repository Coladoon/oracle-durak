PROMPT Проверка Daily, аналитики и ботов

DECLARE
    v_creator        NUMBER;
    v_second         NUMBER;
    v_added_bot      NUMBER;
    v_daily_id       NUMBER;
    v_daily_game     NUMBER;
    v_bot_game       NUMBER;
    v_attacker_seat  NUMBER;
    v_defender_seat  NUMBER;
    v_attacker_id    NUMBER;
    v_defender_id    NUMBER;
    v_seat_no        NUMBER;
    v_seed_text      VARCHAR2(128);
    v_rules_version  VARCHAR2(20);
    v_value          NUMBER;
BEGIN
    SAVEPOINT before_extensions_test;

    v_creator := durak_id_seq.NEXTVAL;
    v_second := durak_id_seq.NEXTVAL;

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_creator, 'Extensions Creator', 'BOT', 'NORMAL'
    );

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_second, 'Extensions Second', 'BOT', 'HARD'
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
    SET hand_count = 1
    WHERE game_id = v_daily_game;

    durak_engine.attack(v_attacker_id, v_daily_game, '6C');
    durak_engine.defend(v_defender_id, v_daily_game, '7C', 1);
    durak_engine.pass_throw(v_attacker_id, v_daily_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_daily_result
    WHERE daily_id = v_daily_id
      AND game_id = v_daily_game
      AND result_code = 'DRAW';
    durak_test.assert_number(
        'Завершение Daily автоматически записывает оба результата',
        2,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM v_analytics
    WHERE game_id = v_daily_game
      AND rounds_count = 1
      AND defenses_count = 1;
    durak_test.assert_number(
        'V_ANALYTICS агрегирует завершённую партию',
        1,
        v_value
    );

    durak_engine.create_game(
        p_creator_player_id => v_creator,
        p_seed_text => 'bot-integration-seed',
        p_game_id => v_bot_game
    );

    durak_engine.add_bot(
        p_actor_player_id => v_creator,
        p_game_id => v_bot_game,
        p_bot_level => 'EASY',
        p_bot_player_id => v_added_bot,
        p_seat_no => v_seat_no
    );

    durak_engine.start_game(v_creator, v_bot_game);
    durak_bot.play_until_human(v_bot_game, 5);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_bot_decision
    WHERE game_id = v_bot_game
      AND event_id IS NOT NULL;
    durak_test.assert_number(
        'Боты записали пять последовательных решений',
        5,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_event
    WHERE game_id = v_bot_game
      AND event_type = 'BOT_DECISION'
      AND event_source = 'BOT';
    durak_test.assert_number(
        'Решения ботов присутствуют в протоколе',
        5,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_player
    WHERE player_id = v_added_bot
      AND player_type = 'BOT'
      AND bot_level = 'EASY';
    durak_test.assert_number(
        'Создан бот выбранного уровня сложности',
        1,
        v_value
    );

    ROLLBACK TO before_extensions_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_extensions_test;
        RAISE;
END;
/
