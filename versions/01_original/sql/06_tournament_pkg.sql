PROMPT Создание турнирного автомата DURAK_TOURNAMENT_PKG

CREATE OR REPLACE PACKAGE BODY durak_tournament_pkg AS
    TYPE t_number_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    PROCEDURE fail (
        p_code    IN NUMBER,
        p_message IN VARCHAR2
    ) IS
    BEGIN
        RAISE_APPLICATION_ERROR(p_code, p_message);
    END fail;

    FUNCTION normalized_flag (
        p_value IN VARCHAR2,
        p_name  IN VARCHAR2
    ) RETURN CHAR DETERMINISTIC IS
        v_value VARCHAR2(10) := UPPER(TRIM(p_value));
    BEGIN
        IF v_value IS NULL OR v_value NOT IN ('Y', 'N') THEN
            fail(-20603, p_name || ' должен иметь значение Y или N.');
        END IF;
        RETURN v_value;
    END normalized_flag;

    PROCEDURE require_player (
        p_player_id IN NUMBER
    ) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM durak_player
        WHERE player_id = p_player_id;

        IF v_count = 0 THEN
            fail(-20604, 'Игрок ' || p_player_id || ' не найден.');
        END IF;
    END require_player;

    PROCEDURE lock_tournament (
        p_tournament_id IN NUMBER,
        p_tournament    OUT durak_tournament%ROWTYPE
    ) IS
    BEGIN
        BEGIN
            SELECT *
            INTO p_tournament
            FROM durak_tournament
            WHERE tournament_id = p_tournament_id
            FOR UPDATE WAIT 5;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fail(-20601, 'Турнир ' || p_tournament_id || ' не найден.');
            WHEN OTHERS THEN
                IF SQLCODE IN (-54, -30006) THEN
                    fail(-20602, 'Турнир занят другой операцией. Повторите запрос.');
                END IF;
                RAISE;
        END;
    END lock_tournament;

    PROCEDURE require_tournament_actor (
        p_actor_player_id IN NUMBER,
        p_tournament      IN durak_tournament%ROWTYPE,
        p_creator_only    IN BOOLEAN DEFAULT FALSE
    ) IS
        v_count NUMBER;
    BEGIN
        IF p_actor_player_id = p_tournament.created_by_player_id THEN
            RETURN;
        END IF;

        IF p_creator_only THEN
            fail(-20605, 'Эту операцию может выполнить только создатель турнира.');
        END IF;

        SELECT COUNT(*)
        INTO v_count
        FROM durak_tournament_player
        WHERE tournament_id = p_tournament.tournament_id
          AND player_id = p_actor_player_id;

        IF v_count = 0 THEN
            fail(-20606, 'Операция доступна только участнику турнира.');
        END IF;
    END require_tournament_actor;

    PROCEDURE finish_with_champion (
        p_tournament_id   IN NUMBER,
        p_champion_id     IN NUMBER,
        p_finish_reason   IN VARCHAR2
    ) IS
    BEGIN
        UPDATE durak_tournament_player
        SET player_status = CASE
            WHEN player_id = p_champion_id THEN 'CHAMPION'
            WHEN player_status = 'REGISTERED' THEN 'ELIMINATED'
            WHEN player_status = 'ACTIVE' THEN 'ELIMINATED'
            ELSE player_status
        END
        WHERE tournament_id = p_tournament_id;

        UPDATE durak_tournament
        SET tournament_status = 'FINISHED',
            champion_player_id = p_champion_id,
            finish_reason = p_finish_reason,
            finished_at = SYSTIMESTAMP
        WHERE tournament_id = p_tournament_id;
    END finish_with_champion;

    PROCEDURE create_round_robin_matches (
        p_tournament_id IN NUMBER
    ) IS
        v_slots       t_number_list;
        v_player_count PLS_INTEGER := 0;
        v_slot_count   PLS_INTEGER;
        v_match_no     PLS_INTEGER;
        v_player1      NUMBER;
        v_player2      NUMBER;
        v_last_slot    NUMBER;
    BEGIN
        FOR r IN (
            SELECT player_id
            FROM durak_tournament_player
            WHERE tournament_id = p_tournament_id
            ORDER BY seed_no
        ) LOOP
            v_player_count := v_player_count + 1;
            v_slots(v_player_count) := r.player_id;
        END LOOP;

        v_slot_count := v_player_count;
        IF MOD(v_slot_count, 2) = 1 THEN
            v_slot_count := v_slot_count + 1;
            v_slots(v_slot_count) := NULL;
        END IF;

        FOR v_round_no IN 1 .. v_slot_count - 1 LOOP
            v_match_no := 0;

            FOR v_pair_pos IN 1 .. v_slot_count / 2 LOOP
                v_player1 := v_slots(v_pair_pos);
                v_player2 := v_slots(v_slot_count - v_pair_pos + 1);

                IF v_player1 IS NOT NULL AND v_player2 IS NOT NULL THEN
                    v_match_no := v_match_no + 1;
                    INSERT INTO durak_tournament_match (
                        tournament_match_id,
                        tournament_id,
                        tournament_round_no,
                        match_no,
                        player1_id,
                        player2_id,
                        match_status
                    ) VALUES (
                        durak_id_seq.NEXTVAL,
                        p_tournament_id,
                        v_round_no,
                        v_match_no,
                        v_player1,
                        v_player2,
                        'PLANNED'
                    );
                END IF;
            END LOOP;

            IF v_slot_count > 2 THEN
                v_last_slot := v_slots(v_slot_count);
                FOR v_pos IN REVERSE 3 .. v_slot_count LOOP
                    v_slots(v_pos) := v_slots(v_pos - 1);
                END LOOP;
                v_slots(2) := v_last_slot;
            END IF;
        END LOOP;
    END create_round_robin_matches;

    PROCEDURE create_elimination_round (
        p_tournament_id IN NUMBER,
        p_round_no      IN NUMBER
    ) IS
        v_players     t_number_list;
        v_count       PLS_INTEGER := 0;
        v_match_no    PLS_INTEGER := 0;
        v_pair_count  PLS_INTEGER;
        v_player1     NUMBER;
        v_player2     NUMBER;
    BEGIN
        IF p_round_no = 1 THEN
            FOR r IN (
                SELECT player_id
                FROM durak_tournament_player
                WHERE tournament_id = p_tournament_id
                ORDER BY seed_no
            ) LOOP
                v_count := v_count + 1;
                v_players(v_count) := r.player_id;
            END LOOP;
        ELSE
            FOR r IN (
                SELECT m.winner_player_id
                FROM durak_tournament_match m
                JOIN durak_tournament_player tp
                  ON tp.tournament_id = m.tournament_id
                 AND tp.player_id = m.winner_player_id
                WHERE m.tournament_id = p_tournament_id
                  AND m.tournament_round_no = p_round_no - 1
                  AND m.match_status IN ('FINISHED', 'BYE')
                  AND m.winner_player_id IS NOT NULL
                ORDER BY tp.seed_no
            ) LOOP
                v_count := v_count + 1;
                v_players(v_count) := r.winner_player_id;
            END LOOP;
        END IF;

        IF v_count < 2 THEN
            fail(-20607, 'Недостаточно победителей для формирования следующего раунда.');
        END IF;

        v_pair_count := TRUNC(v_count / 2);
        FOR v_pos IN 1 .. v_pair_count LOOP
            v_player1 := v_players(v_pos);
            v_player2 := v_players(v_count - v_pos + 1);
            v_match_no := v_match_no + 1;

            INSERT INTO durak_tournament_match (
                tournament_match_id,
                tournament_id,
                tournament_round_no,
                match_no,
                player1_id,
                player2_id,
                match_status
            ) VALUES (
                durak_id_seq.NEXTVAL,
                p_tournament_id,
                p_round_no,
                v_match_no,
                v_player1,
                v_player2,
                'PLANNED'
            );
        END LOOP;

        IF MOD(v_count, 2) = 1 THEN
            v_match_no := v_match_no + 1;
            v_player1 := v_players(v_pair_count + 1);

            INSERT INTO durak_tournament_match (
                tournament_match_id,
                tournament_id,
                tournament_round_no,
                match_no,
                player1_id,
                player2_id,
                winner_player_id,
                match_status,
                result_reason,
                finished_at
            ) VALUES (
                durak_id_seq.NEXTVAL,
                p_tournament_id,
                p_round_no,
                v_match_no,
                v_player1,
                NULL,
                v_player1,
                'BYE',
                'AUTOMATIC_BYE',
                SYSTIMESTAMP
            );
        END IF;
    END create_elimination_round;

    PROCEDURE finish_round_robin_if_ready (
        p_tournament_id IN NUMBER
    ) IS
        v_pending_count NUMBER;
        v_champion_id   NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_pending_count
        FROM durak_tournament_match
        WHERE tournament_id = p_tournament_id
          AND match_status IN ('PLANNED', 'ACTIVE');

        IF v_pending_count > 0 THEN
            RETURN;
        END IF;

        SELECT player_id
        INTO v_champion_id
        FROM (
            SELECT player_id
            FROM durak_tournament_player
            WHERE tournament_id = p_tournament_id
            ORDER BY points DESC, wins_count DESC, draws_count DESC, seed_no
        )
        WHERE ROWNUM = 1;

        finish_with_champion(
            p_tournament_id,
            v_champion_id,
            'ROUND_ROBIN_COMPLETE'
        );
    END finish_round_robin_if_ready;

    PROCEDURE progress_elimination (
        p_tournament_id IN NUMBER,
        p_round_no      IN NUMBER
    ) IS
        v_pending_count NUMBER;
        v_winner_count  NUMBER;
        v_champion_id   NUMBER;
        v_next_exists   NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_pending_count
        FROM durak_tournament_match
        WHERE tournament_id = p_tournament_id
          AND tournament_round_no = p_round_no
          AND match_status IN ('PLANNED', 'ACTIVE');

        IF v_pending_count > 0 THEN
            RETURN;
        END IF;

        SELECT COUNT(*), MIN(winner_player_id)
        INTO v_winner_count, v_champion_id
        FROM durak_tournament_match
        WHERE tournament_id = p_tournament_id
          AND tournament_round_no = p_round_no
          AND match_status IN ('FINISHED', 'BYE')
          AND winner_player_id IS NOT NULL;

        IF v_winner_count = 1 THEN
            finish_with_champion(
                p_tournament_id,
                v_champion_id,
                'ELIMINATION_FINAL_COMPLETE'
            );
            RETURN;
        END IF;

        IF v_winner_count < 2 THEN
            fail(-20608, 'Раунд завершён без достаточного числа победителей.');
        END IF;

        SELECT COUNT(*)
        INTO v_next_exists
        FROM durak_tournament_match
        WHERE tournament_id = p_tournament_id
          AND tournament_round_no = p_round_no + 1;

        IF v_next_exists = 0 THEN
            create_elimination_round(p_tournament_id, p_round_no + 1);
        END IF;
    END progress_elimination;

    PROCEDURE create_tournament (
        p_creator_player_id      IN NUMBER,
        p_tournament_name        IN VARCHAR2,
        p_tournament_format      IN VARCHAR2 DEFAULT 'ROUND_ROBIN',
        p_deck_size              IN NUMBER DEFAULT 36,
        p_game_variant           IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode        IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs              IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec       IN NUMBER DEFAULT 60,
        p_idle_timeout_min       IN NUMBER DEFAULT 30,
        p_allow_throw_after_take IN VARCHAR2 DEFAULT 'N',
        p_limit_by_defender_hand IN VARCHAR2 DEFAULT 'Y',
        p_seed_text              IN VARCHAR2 DEFAULT NULL,
        p_tournament_id          OUT NUMBER
    ) IS
        v_name        VARCHAR2(100) := TRIM(p_tournament_name);
        v_format      VARCHAR2(20) := UPPER(TRIM(p_tournament_format));
        v_variant     VARCHAR2(12) := UPPER(TRIM(p_game_variant));
        v_first       VARCHAR2(20) := UPPER(TRIM(p_first_move_mode));
        v_max_pairs   NUMBER;
        v_throw_after CHAR(1);
        v_limit_hand  CHAR(1);
        v_seed        VARCHAR2(128);
    BEGIN
        require_player(p_creator_player_id);

        IF v_name IS NULL OR LENGTHB(v_name) > 100 THEN
            fail(-20609, 'Название турнира должно занимать от 1 до 100 байт.');
        END IF;
        IF v_format IS NULL
           OR v_format NOT IN ('ROUND_ROBIN', 'SINGLE_ELIMINATION') THEN
            fail(-20610, 'Формат должен быть ROUND_ROBIN или SINGLE_ELIMINATION.');
        END IF;
        IF p_deck_size IS NULL OR p_deck_size NOT IN (36, 52) THEN
            fail(-20611, 'Размер колоды должен быть 36 или 52.');
        END IF;
        IF v_variant IS NULL OR v_variant NOT IN ('PODKIDNOY', 'PEREVODNOY') THEN
            fail(-20612, 'Вариант должен быть PODKIDNOY или PEREVODNOY.');
        END IF;
        IF v_first IS NULL OR v_first NOT IN ('LOWEST_TRUMP', 'SEEDED_RANDOM') THEN
            fail(-20613, 'Неизвестный способ выбора первого хода.');
        END IF;
        IF p_turn_timeout_sec IS NULL
           OR p_turn_timeout_sec < 0
           OR p_turn_timeout_sec > 86400
           OR p_turn_timeout_sec <> TRUNC(p_turn_timeout_sec) THEN
            fail(-20614, 'Таймер хода должен быть целым числом от 0 до 86400.');
        END IF;
        IF p_idle_timeout_min IS NULL
           OR p_idle_timeout_min < 1
           OR p_idle_timeout_min > 10080
           OR p_idle_timeout_min <> TRUNC(p_idle_timeout_min) THEN
            fail(-20615, 'Таймер простоя должен быть целым числом от 1 до 10080.');
        END IF;

        v_max_pairs := NVL(p_max_pairs, durak_rules.default_max_pairs(p_deck_size));
        IF v_max_pairs < 1
           OR v_max_pairs > durak_rules.default_max_pairs(p_deck_size)
           OR v_max_pairs <> TRUNC(v_max_pairs) THEN
            fail(-20616, 'Некорректный максимальный размер стола.');
        END IF;

        v_throw_after := normalized_flag(
            p_allow_throw_after_take,
            'allow_throw_after_take'
        );
        v_limit_hand := normalized_flag(
            p_limit_by_defender_hand,
            'limit_by_defender_hand'
        );
        v_seed := CASE
            WHEN TRIM(p_seed_text) IS NULL THEN durak_random.generated_seed
            ELSE durak_random.normalize_seed(p_seed_text)
        END;

        p_tournament_id := durak_id_seq.NEXTVAL;
        INSERT INTO durak_tournament (
            tournament_id,
            tournament_name,
            created_by_player_id,
            tournament_format,
            deck_size,
            game_variant,
            first_move_mode,
            max_pairs,
            allow_throw_after_take,
            limit_by_defender_hand,
            turn_timeout_sec,
            idle_timeout_min,
            seed_text,
            seed_hash
        ) VALUES (
            p_tournament_id,
            v_name,
            p_creator_player_id,
            v_format,
            p_deck_size,
            v_variant,
            v_first,
            v_max_pairs,
            v_throw_after,
            v_limit_hand,
            p_turn_timeout_sec,
            p_idle_timeout_min,
            v_seed,
            durak_random.hash_text(v_seed)
        );

        INSERT INTO durak_tournament_player (
            tournament_id,
            player_id,
            player_status
        ) VALUES (
            p_tournament_id,
            p_creator_player_id,
            'REGISTERED'
        );
    END create_tournament;

    PROCEDURE join_tournament (
        p_player_id     IN NUMBER,
        p_tournament_id IN NUMBER
    ) IS
        v_tournament durak_tournament%ROWTYPE;
        v_count      NUMBER;
    BEGIN
        require_player(p_player_id);
        lock_tournament(p_tournament_id, v_tournament);

        IF v_tournament.tournament_status <> 'LOBBY' THEN
            fail(-20617, 'Присоединиться можно только к турниру в лобби.');
        END IF;

        SELECT COUNT(*)
        INTO v_count
        FROM durak_tournament_player
        WHERE tournament_id = p_tournament_id;

        IF v_count >= 16 THEN
            fail(-20618, 'В турнире уже заняты все 16 мест.');
        END IF;

        BEGIN
            INSERT INTO durak_tournament_player (
                tournament_id,
                player_id,
                player_status
            ) VALUES (
                p_tournament_id,
                p_player_id,
                'REGISTERED'
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                fail(-20619, 'Игрок уже зарегистрирован в этом турнире.');
        END;
    END join_tournament;

    PROCEDURE add_bot (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER,
        p_bot_level       IN VARCHAR2 DEFAULT 'NORMAL',
        p_bot_player_id   OUT NUMBER
    ) IS
        v_tournament durak_tournament%ROWTYPE;
        v_level      VARCHAR2(10) := UPPER(TRIM(p_bot_level));
        v_count      NUMBER;
    BEGIN
        lock_tournament(p_tournament_id, v_tournament);
        require_tournament_actor(p_actor_player_id, v_tournament, TRUE);

        IF v_tournament.tournament_status <> 'LOBBY' THEN
            fail(-20620, 'Добавить бота можно только до запуска турнира.');
        END IF;
        IF v_level IS NULL OR v_level NOT IN ('EASY', 'NORMAL', 'HARD') THEN
            fail(-20621, 'Уровень бота должен быть EASY, NORMAL или HARD.');
        END IF;

        SELECT COUNT(*)
        INTO v_count
        FROM durak_tournament_player
        WHERE tournament_id = p_tournament_id;

        IF v_count >= 16 THEN
            fail(-20618, 'В турнире уже заняты все 16 мест.');
        END IF;

        p_bot_player_id := durak_id_seq.NEXTVAL;
        INSERT INTO durak_player (
            player_id,
            display_name,
            player_type,
            bot_level
        ) VALUES (
            p_bot_player_id,
            'Турнирный бот ' || INITCAP(LOWER(v_level)) || ' #' || p_bot_player_id,
            'BOT',
            v_level
        );

        INSERT INTO durak_tournament_player (
            tournament_id,
            player_id,
            player_status
        ) VALUES (
            p_tournament_id,
            p_bot_player_id,
            'REGISTERED'
        );
    END add_bot;

    PROCEDURE start_tournament (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER
    ) IS
        v_tournament  durak_tournament%ROWTYPE;
        v_player_count NUMBER;
        v_seed_no       PLS_INTEGER := 0;
    BEGIN
        lock_tournament(p_tournament_id, v_tournament);
        require_tournament_actor(p_actor_player_id, v_tournament, TRUE);

        IF v_tournament.tournament_status <> 'LOBBY' THEN
            fail(-20622, 'Турнир уже запущен или завершён.');
        END IF;

        SELECT COUNT(*)
        INTO v_player_count
        FROM durak_tournament_player
        WHERE tournament_id = p_tournament_id;

        IF v_player_count NOT BETWEEN 2 AND 16 THEN
            fail(-20623, 'Для старта требуется от 2 до 16 участников.');
        END IF;

        FOR r IN (
            SELECT player_id
            FROM durak_tournament_player
            WHERE tournament_id = p_tournament_id
            ORDER BY RAWTOHEX(
                durak_random.hash_text(
                    v_tournament.seed_text || ':TOURNAMENT-SEED:' || player_id
                )
            ), player_id
        ) LOOP
            v_seed_no := v_seed_no + 1;
            UPDATE durak_tournament_player
            SET seed_no = v_seed_no,
                player_status = 'ACTIVE'
            WHERE tournament_id = p_tournament_id
              AND player_id = r.player_id;
        END LOOP;

        IF v_tournament.tournament_format = 'ROUND_ROBIN' THEN
            create_round_robin_matches(p_tournament_id);
        ELSE
            create_elimination_round(p_tournament_id, 1);
        END IF;

        UPDATE durak_tournament
        SET tournament_status = 'ACTIVE',
            started_at = SYSTIMESTAMP
        WHERE tournament_id = p_tournament_id;
    END start_tournament;

    PROCEDURE start_match (
        p_actor_player_id     IN NUMBER,
        p_tournament_match_id IN NUMBER,
        p_game_id             OUT NUMBER
    ) IS
        v_tournament_id NUMBER;
        v_tournament    durak_tournament%ROWTYPE;
        v_match         durak_tournament_match%ROWTYPE;
        v_seat_no       NUMBER;
        v_match_seed    VARCHAR2(128);
    BEGIN
        BEGIN
            SELECT tournament_id
            INTO v_tournament_id
            FROM durak_tournament_match
            WHERE tournament_match_id = p_tournament_match_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fail(-20624, 'Турнирный матч ' || p_tournament_match_id || ' не найден.');
        END;

        lock_tournament(v_tournament_id, v_tournament);
        require_tournament_actor(p_actor_player_id, v_tournament, FALSE);

        BEGIN
            SELECT *
            INTO v_match
            FROM durak_tournament_match
            WHERE tournament_match_id = p_tournament_match_id
            FOR UPDATE WAIT 5;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE IN (-54, -30006) THEN
                    fail(-20625, 'Матч занят другой операцией. Повторите запрос.');
                END IF;
                RAISE;
        END;

        IF v_tournament.tournament_status <> 'ACTIVE' THEN
            fail(-20626, 'Запускать матчи можно только в активном турнире.');
        END IF;
        IF v_match.match_status <> 'PLANNED' THEN
            fail(-20627, 'Матч уже запущен, завершён или является автоматическим проходом.');
        END IF;
        IF v_match.player2_id IS NULL THEN
            fail(-20628, 'Матч без второго участника запускать не требуется.');
        END IF;

        -- Хеш даёт фиксированные 64 ASCII-символа и не переполняет
        -- ограничение seed в 128 байт даже для многобайтного исходного текста.
        v_match_seed := RAWTOHEX(
            durak_random.hash_text(
                v_tournament.seed_text
                || ':ROUND:' || v_match.tournament_round_no
                || ':MATCH:' || v_match.match_no
            )
        );

        durak_engine.create_game(
            p_creator_player_id      => v_match.player1_id,
            p_deck_size              => v_tournament.deck_size,
            p_game_variant           => v_tournament.game_variant,
            p_first_move_mode        => v_tournament.first_move_mode,
            p_max_pairs              => v_tournament.max_pairs,
            p_turn_timeout_sec       => v_tournament.turn_timeout_sec,
            p_idle_timeout_min       => v_tournament.idle_timeout_min,
            p_allow_throw_after_take => v_tournament.allow_throw_after_take,
            p_limit_by_defender_hand => v_tournament.limit_by_defender_hand,
            p_seed_text              => v_match_seed,
            p_game_id                => p_game_id
        );

        durak_engine.join_game(v_match.player2_id, p_game_id, v_seat_no);
        durak_engine.start_game(v_match.player1_id, p_game_id);

        UPDATE durak_tournament_match
        SET game_id = p_game_id,
            match_status = 'ACTIVE'
        WHERE tournament_match_id = p_tournament_match_id;
    END start_match;

    PROCEDURE cancel_tournament (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER
    ) IS
        v_tournament  durak_tournament%ROWTYPE;
        v_active_count NUMBER;
    BEGIN
        lock_tournament(p_tournament_id, v_tournament);
        require_tournament_actor(p_actor_player_id, v_tournament, TRUE);

        IF v_tournament.tournament_status NOT IN ('LOBBY', 'ACTIVE') THEN
            fail(-20629, 'Завершённый или отменённый турнир изменить нельзя.');
        END IF;

        SELECT COUNT(*)
        INTO v_active_count
        FROM durak_tournament_match
        WHERE tournament_id = p_tournament_id
          AND match_status = 'ACTIVE';

        IF v_active_count > 0 THEN
            fail(
                -20630,
                'Нельзя отменить турнир во время активного матча. Сначала завершите матч.'
            );
        END IF;

        UPDATE durak_tournament_match
        SET match_status = 'CANCELLED',
            result_reason = 'TOURNAMENT_CANCELLED',
            finished_at = SYSTIMESTAMP
        WHERE tournament_id = p_tournament_id
          AND match_status = 'PLANNED';

        UPDATE durak_tournament
        SET tournament_status = 'CANCELLED',
            finish_reason = 'CANCELLED_BY_CREATOR',
            finished_at = SYSTIMESTAMP
        WHERE tournament_id = p_tournament_id;
    END cancel_tournament;

    PROCEDURE record_game_result (
        p_game_id IN NUMBER
    ) IS
        v_tournament_id NUMBER;
        v_match_id      NUMBER;
        v_tournament    durak_tournament%ROWTYPE;
        v_match         durak_tournament_match%ROWTYPE;
        v_game_status   durak_game.game_status%TYPE;
        v_game_winner   NUMBER;
        v_draw_count    NUMBER;
        v_winner_id     NUMBER;
        v_loser_id      NUMBER;
        v_result_reason VARCHAR2(40);
    BEGIN
        BEGIN
            SELECT tournament_id, tournament_match_id
            INTO v_tournament_id, v_match_id
            FROM durak_tournament_match
            WHERE game_id = p_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN;
        END;

        lock_tournament(v_tournament_id, v_tournament);

        BEGIN
            SELECT *
            INTO v_match
            FROM durak_tournament_match
            WHERE tournament_match_id = v_match_id
            FOR UPDATE WAIT 5;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE IN (-54, -30006) THEN
                    fail(-20625, 'Матч занят другой операцией. Повторите запрос.');
                END IF;
                RAISE;
        END;

        IF v_tournament.tournament_status <> 'ACTIVE'
           OR v_match.match_status <> 'ACTIVE' THEN
            RETURN;
        END IF;

        SELECT game_status
        INTO v_game_status
        FROM durak_game
        WHERE game_id = p_game_id;

        IF v_game_status = 'EXPIRED' THEN
            -- Просроченный матч не должен блокировать турнир навсегда.
            -- В круговом турнире это ничья; в олимпийской сетке применяется
            -- тот же детерминированный seed-tiebreak, что и для обычной ничьей.
            v_game_winner := NULL;
            v_draw_count := 2;
        ELSIF v_game_status <> 'FINISHED' THEN
            fail(-20631, 'Результат можно записать только после завершения партии.');
        ELSE
            SELECT
                MAX(CASE WHEN result_code = 'WIN' THEN player_id END),
                SUM(CASE WHEN result_code = 'DRAW' THEN 1 ELSE 0 END)
            INTO v_game_winner, v_draw_count
            FROM durak_game_player
            WHERE game_id = p_game_id
              AND player_id IN (v_match.player1_id, v_match.player2_id);
        END IF;

        IF v_game_winner IS NOT NULL THEN
            v_winner_id := v_game_winner;
            v_loser_id := CASE
                WHEN v_winner_id = v_match.player1_id THEN v_match.player2_id
                ELSE v_match.player1_id
            END;
            v_result_reason := 'GAME_WIN';

            UPDATE durak_tournament_player
            SET points = points + 3,
                wins_count = wins_count + 1
            WHERE tournament_id = v_tournament_id
              AND player_id = v_winner_id;

            UPDATE durak_tournament_player
            SET losses_count = losses_count + 1
            WHERE tournament_id = v_tournament_id
              AND player_id = v_loser_id;
        ELSIF v_draw_count = 2 THEN
            UPDATE durak_tournament_player
            SET points = points + 1,
                draws_count = draws_count + 1
            WHERE tournament_id = v_tournament_id
              AND player_id IN (v_match.player1_id, v_match.player2_id);

            IF v_tournament.tournament_format = 'SINGLE_ELIMINATION' THEN
                SELECT player_id
                INTO v_winner_id
                FROM (
                    SELECT player_id
                    FROM durak_tournament_player
                    WHERE tournament_id = v_tournament_id
                      AND player_id IN (v_match.player1_id, v_match.player2_id)
                    ORDER BY seed_no
                )
                WHERE ROWNUM = 1;

                v_loser_id := CASE
                    WHEN v_winner_id = v_match.player1_id THEN v_match.player2_id
                    ELSE v_match.player1_id
                END;
                v_result_reason := CASE
                    WHEN v_game_status = 'EXPIRED'
                        THEN 'EXPIRED_SEED_TIEBREAK'
                    ELSE 'DRAW_SEED_TIEBREAK'
                END;
            ELSE
                v_winner_id := NULL;
                v_loser_id := NULL;
                v_result_reason := CASE
                    WHEN v_game_status = 'EXPIRED' THEN 'GAME_EXPIRED_DRAW'
                    ELSE 'GAME_DRAW'
                END;
            END IF;
        ELSE
            fail(-20632, 'У завершённой партии нет однозначного результата.');
        END IF;

        UPDATE durak_tournament_match
        SET winner_player_id = v_winner_id,
            match_status = 'FINISHED',
            result_reason = v_result_reason,
            finished_at = SYSTIMESTAMP
        WHERE tournament_match_id = v_match_id;

        IF v_tournament.tournament_format = 'SINGLE_ELIMINATION' THEN
            IF v_loser_id IS NOT NULL THEN
                UPDATE durak_tournament_player
                SET player_status = 'ELIMINATED'
                WHERE tournament_id = v_tournament_id
                  AND player_id = v_loser_id;
            END IF;

            progress_elimination(
                v_tournament_id,
                v_match.tournament_round_no
            );
        ELSE
            finish_round_robin_if_ready(v_tournament_id);
        END IF;
    END record_game_result;
END durak_tournament_pkg;
/

SHOW ERRORS PACKAGE BODY durak_tournament_pkg
