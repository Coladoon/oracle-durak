PROMPT Проверка кругового турнира и олимпийской сетки

DECLARE
    v_rr_player1      NUMBER;
    v_rr_player2      NUMBER;
    v_rr_player3      NUMBER;
    v_rr_tournament   NUMBER;
    v_se_player1      NUMBER;
    v_se_player2      NUMBER;
    v_se_player3      NUMBER;
    v_se_tournament   NUMBER;
    v_idle_player1    NUMBER;
    v_idle_player2    NUMBER;
    v_idle_tournament NUMBER;
    v_idle_game       NUMBER;
    v_match_id        NUMBER;
    v_expected_player NUMBER;
    v_value           NUMBER;
    v_games_played    NUMBER;
    v_status          VARCHAR2(12);

    PROCEDURE create_test_bot (
        p_name      IN VARCHAR2,
        p_player_id OUT NUMBER
    ) IS
    BEGIN
        p_player_id := durak_id_seq.NEXTVAL;
        INSERT INTO durak_player (
            player_id, display_name, player_type, bot_level
        ) VALUES (
            p_player_id, p_name, 'BOT', 'NORMAL'
        );
    END create_test_bot;

    PROCEDURE finish_match_as_draw (
        p_match_id IN NUMBER
    ) IS
        v_game_id       NUMBER;
        v_actor_id      NUMBER;
        v_attacker_id   NUMBER;
        v_defender_id   NUMBER;
        v_attacker_seat NUMBER;
        v_defender_seat NUMBER;
    BEGIN
        SELECT player1_id
        INTO v_actor_id
        FROM durak_tournament_match
        WHERE tournament_match_id = p_match_id;

        durak_tournament_pkg.start_match(
            p_actor_player_id     => v_actor_id,
            p_tournament_match_id => p_match_id,
            p_game_id             => v_game_id
        );

        SELECT attacker_seat_no, defender_seat_no
        INTO v_attacker_seat, v_defender_seat
        FROM durak_game
        WHERE game_id = v_game_id;

        SELECT player_id
        INTO v_attacker_id
        FROM durak_game_player
        WHERE game_id = v_game_id
          AND seat_no = v_attacker_seat;

        SELECT player_id
        INTO v_defender_id
        FROM durak_game_player
        WHERE game_id = v_game_id
          AND seat_no = v_defender_seat;

        -- Оставляем по одной гарантированно совместимой карте и пустой талон.
        UPDATE durak_game_card
        SET card_zone = 'DISCARD',
            owner_seat_no = NULL,
            table_pair_no = NULL,
            received_seq = NULL,
            is_face_up = 'Y'
        WHERE game_id = v_game_id;

        UPDATE durak_game_card
        SET card_zone = 'HAND',
            owner_seat_no = v_attacker_seat,
            received_seq = 1,
            is_face_up = 'N'
        WHERE game_id = v_game_id
          AND card_id = (
              SELECT card_id FROM durak_card WHERE card_code = '6C'
          );

        UPDATE durak_game_card
        SET card_zone = 'HAND',
            owner_seat_no = v_defender_seat,
            received_seq = 1,
            is_face_up = 'N'
        WHERE game_id = v_game_id
          AND card_id = (
              SELECT card_id FROM durak_card WHERE card_code = '7C'
          );

        UPDATE durak_game_player
        SET hand_count = 1
        WHERE game_id = v_game_id;

        durak_engine.attack(v_attacker_id, v_game_id, '6C');
        durak_engine.defend(v_defender_id, v_game_id, '7C', 1);
        durak_engine.pass_throw(v_attacker_id, v_game_id);
    END finish_match_as_draw;
BEGIN
    SAVEPOINT before_tournament_test;

    create_test_bot('Round Robin 1', v_rr_player1);
    create_test_bot('Round Robin 2', v_rr_player2);
    create_test_bot('Round Robin 3', v_rr_player3);

    durak_tournament_pkg.create_tournament(
        p_creator_player_id => v_rr_player1,
        p_tournament_name   => 'Тест кругового турнира',
        p_tournament_format => 'ROUND_ROBIN',
        p_seed_text         => 'round-robin-test-seed',
        p_tournament_id     => v_rr_tournament
    );
    durak_tournament_pkg.join_tournament(v_rr_player2, v_rr_tournament);
    durak_tournament_pkg.join_tournament(v_rr_player3, v_rr_tournament);
    durak_tournament_pkg.start_tournament(v_rr_player1, v_rr_tournament);

    SELECT COUNT(*), MAX(tournament_round_no)
    INTO v_value, v_games_played
    FROM durak_tournament_match
    WHERE tournament_id = v_rr_tournament;
    durak_test.assert_number('Круговой турнир из трёх игроков создаёт 3 матча', 3, v_value);
    durak_test.assert_number('Круговой турнир распределяет матчи по 3 раундам', 3, v_games_played);

    v_games_played := 0;
    LOOP
        SELECT MIN(tournament_match_id)
        INTO v_match_id
        FROM durak_tournament_match
        WHERE tournament_id = v_rr_tournament
          AND match_status = 'PLANNED';

        EXIT WHEN v_match_id IS NULL;
        finish_match_as_draw(v_match_id);
        v_games_played := v_games_played + 1;
    END LOOP;

    durak_test.assert_number('Все круговые матчи были сыграны', 3, v_games_played);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament
    WHERE tournament_id = v_rr_tournament
      AND tournament_status = 'FINISHED'
      AND champion_player_id IS NOT NULL;
    durak_test.assert_number('Круговой турнир автоматически завершён', 1, v_value);

    SELECT player_id
    INTO v_expected_player
    FROM durak_tournament_player
    WHERE tournament_id = v_rr_tournament
      AND seed_no = 1;

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament
    WHERE tournament_id = v_rr_tournament
      AND champion_player_id = v_expected_player;
    durak_test.assert_number('При равенстве очков побеждает первый seed', 1, v_value);

    SELECT SUM(points)
    INTO v_value
    FROM durak_tournament_player
    WHERE tournament_id = v_rr_tournament;
    durak_test.assert_number('Три ничьи начисляют участникам 6 очков', 6, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM v_tournament_standings
    WHERE tournament_id = v_rr_tournament;
    durak_test.assert_number('Турнирное табло показывает трёх участников', 3, v_value);

    create_test_bot('Elimination 1', v_se_player1);
    create_test_bot('Elimination 2', v_se_player2);
    create_test_bot('Elimination 3', v_se_player3);

    durak_tournament_pkg.create_tournament(
        p_creator_player_id => v_se_player1,
        p_tournament_name   => 'Тест олимпийской сетки',
        p_tournament_format => 'SINGLE_ELIMINATION',
        p_seed_text         => RPAD(UNISTR('\044F'), 64, UNISTR('\044F')),
        p_tournament_id     => v_se_tournament
    );
    durak_tournament_pkg.join_tournament(v_se_player2, v_se_tournament);
    durak_tournament_pkg.join_tournament(v_se_player3, v_se_tournament);
    durak_tournament_pkg.start_tournament(v_se_player1, v_se_tournament);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament_match
    WHERE tournament_id = v_se_tournament
      AND tournament_round_no = 1
      AND match_status = 'BYE';
    durak_test.assert_number('Нечётная олимпийская сетка создаёт один автопроход', 1, v_value);

    v_games_played := 0;
    LOOP
        SELECT tournament_status
        INTO v_status
        FROM durak_tournament
        WHERE tournament_id = v_se_tournament;

        EXIT WHEN v_status = 'FINISHED';

        SELECT MIN(tournament_match_id)
        INTO v_match_id
        FROM durak_tournament_match
        WHERE tournament_id = v_se_tournament
          AND match_status = 'PLANNED';

        IF v_match_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20897, 'Олимпийская сетка не создала следующий матч.');
        END IF;

        finish_match_as_draw(v_match_id);
        v_games_played := v_games_played + 1;
    END LOOP;

    durak_test.assert_number('Олимпийский турнир из трёх игроков требует 2 партии', 2, v_games_played);

    SELECT MAX(LENGTHB(g.seed_text))
    INTO v_value
    FROM durak_tournament_match m
    JOIN durak_game g ON g.game_id = m.game_id
    WHERE m.tournament_id = v_se_tournament;
    durak_test.assert_between(
        'Unicode-seed турнира безопасно преобразуется в seed матча',
        v_value,
        1,
        128
    );

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament_match
    WHERE tournament_id = v_se_tournament;
    durak_test.assert_number('Олимпийская сетка содержит проход, полуфинал и финал', 3, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament_player
    WHERE tournament_id = v_se_tournament
      AND player_status = 'CHAMPION';
    durak_test.assert_number('В олимпийской сетке определён один чемпион', 1, v_value);

    create_test_bot('Idle Tournament 1', v_idle_player1);
    create_test_bot('Idle Tournament 2', v_idle_player2);

    durak_tournament_pkg.create_tournament(
        p_creator_player_id => v_idle_player1,
        p_tournament_name   => 'Тест простоя турнира',
        p_tournament_format => 'ROUND_ROBIN',
        p_idle_timeout_min  => 1,
        p_seed_text         => 'idle-tournament-seed',
        p_tournament_id     => v_idle_tournament
    );
    durak_tournament_pkg.join_tournament(v_idle_player2, v_idle_tournament);
    durak_tournament_pkg.start_tournament(v_idle_player1, v_idle_tournament);

    SELECT tournament_match_id
    INTO v_match_id
    FROM durak_tournament_match
    WHERE tournament_id = v_idle_tournament;

    durak_tournament_pkg.start_match(
        p_actor_player_id     => v_idle_player1,
        p_tournament_match_id => v_match_id,
        p_game_id             => v_idle_game
    );

    UPDATE durak_game
    SET last_activity_at = SYSTIMESTAMP - NUMTODSINTERVAL(2, 'MINUTE')
    WHERE game_id = v_idle_game;

    durak_engine.expire_idle_game(v_idle_game);

    SELECT COUNT(*)
    INTO v_value
    FROM durak_tournament_match m
    JOIN durak_tournament t ON t.tournament_id = m.tournament_id
    WHERE m.tournament_match_id = v_match_id
      AND m.match_status = 'FINISHED'
      AND m.result_reason = 'GAME_EXPIRED_DRAW'
      AND t.tournament_status = 'FINISHED';
    durak_test.assert_number(
        'Простой завершает турнирный матч и сам турнир',
        1,
        v_value
    );

    ROLLBACK TO before_tournament_test;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_tournament_test;
        RAISE;
END;
/
