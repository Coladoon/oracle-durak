PROMPT Создание защищённых представлений проекта DURAK

CREATE OR REPLACE VIEW v_current_player AS
SELECT
    p.player_id,
    p.db_username,
    p.display_name,
    p.player_type,
    p.locale_code,
    p.time_zone_name
FROM durak_player p
WHERE p.db_username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));

CREATE OR REPLACE VIEW v_game_status AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
)
SELECT
    g.game_id,
    g.daily_id,
    g.game_status,
    g.phase,
    g.deck_size,
    g.game_variant,
    g.first_move_mode,
    g.target_hand_size,
    g.max_pairs,
    g.allow_throw_after_take,
    g.limit_by_defender_hand,
    g.turn_timeout_sec,
    g.current_round_no,
    g.trump_suit,
    trump_card.card_code AS trump_card_code,
    (
        SELECT COUNT(*)
        FROM durak_game_card talon_card
        WHERE talon_card.game_id = g.game_id
          AND talon_card.card_zone = 'TALON'
    ) AS talon_count,
    viewer.player_id AS viewer_player_id,
    viewer.seat_no AS viewer_seat_no,
    listed.seat_no,
    listed.player_id,
    listed_player.display_name,
    listed_player.player_type,
    listed.player_status,
    listed.hand_count,
    g.attacker_seat_no,
    attacker_player.display_name AS attacker_name,
    g.defender_seat_no,
    defender_player.display_name AS defender_name,
    g.current_actor_seat_no,
    actor_player.display_name AS current_actor_name,
    CASE
        WHEN g.game_status <> 'ACTIVE' OR viewer.player_status <> 'ACTIVE'
            THEN 'VIEW_ONLY'
        WHEN g.current_actor_seat_no <> viewer.seat_no
            THEN 'WAIT'
        WHEN g.phase = 'WAIT_ATTACK'
            THEN 'ATTACK'
        WHEN g.phase = 'WAIT_DEFENSE'
             AND viewer.seat_no = g.defender_seat_no
             AND g.game_variant = 'PEREVODNOY'
             AND NVL(current_round.defense_started, 'N') = 'N'
            THEN 'DEFEND,TRANSFER,TAKE'
        WHEN g.phase = 'WAIT_DEFENSE'
             AND viewer.seat_no = g.defender_seat_no
            THEN 'DEFEND,TAKE'
        WHEN g.phase IN ('WAIT_THROW', 'TAKE_THROW')
            THEN 'THROW_IN,PASS'
        ELSE 'WAIT'
    END AS my_allowed_actions,
    g.action_deadline_at,
    g.last_activity_at,
    g.started_at,
    g.finished_at,
    g.finish_reason,
    g.fool_seat_no,
    fool_player.display_name AS fool_name,
    g.version_no
FROM session_player sp
JOIN durak_game_player viewer
  ON viewer.player_id = sp.player_id
JOIN durak_game g
  ON g.game_id = viewer.game_id
LEFT JOIN durak_round current_round
  ON current_round.game_id = g.game_id
 AND current_round.round_no = g.current_round_no
JOIN durak_game_player listed
  ON listed.game_id = g.game_id
JOIN durak_player listed_player
  ON listed_player.player_id = listed.player_id
LEFT JOIN durak_card trump_card
  ON trump_card.card_id = g.trump_card_id
LEFT JOIN durak_game_player attacker
  ON attacker.game_id = g.game_id
 AND attacker.seat_no = g.attacker_seat_no
LEFT JOIN durak_player attacker_player
  ON attacker_player.player_id = attacker.player_id
LEFT JOIN durak_game_player defender
  ON defender.game_id = g.game_id
 AND defender.seat_no = g.defender_seat_no
LEFT JOIN durak_player defender_player
  ON defender_player.player_id = defender.player_id
LEFT JOIN durak_game_player actor
  ON actor.game_id = g.game_id
 AND actor.seat_no = g.current_actor_seat_no
LEFT JOIN durak_player actor_player
  ON actor_player.player_id = actor.player_id
LEFT JOIN durak_game_player fool
  ON fool.game_id = g.game_id
 AND fool.seat_no = g.fool_seat_no
LEFT JOIN durak_player fool_player
  ON fool_player.player_id = fool.player_id;

CREATE OR REPLACE VIEW v_table AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
)
SELECT
    g.game_id,
    g.current_round_no AS round_no,
    viewer.seat_no AS viewer_seat_no,
    g.phase,
    g.attacker_seat_no,
    g.defender_seat_no,
    pair_row.pair_no,
    pair_row.attacking_seat_no,
    attacking_player.display_name AS attacking_player_name,
    attack_card.card_code AS attack_card_code,
    attack_card.rank_code AS attack_rank,
    attack_card.suit_code AS attack_suit,
    pair_row.defending_seat_no,
    defending_player.display_name AS defending_player_name,
    defense_card.card_code AS defense_card_code,
    pair_row.pair_status,
    CASE
        WHEN pair_row.pair_status IN ('COVERED', 'DISCARDED') THEN 'Y'
        ELSE 'N'
    END AS is_beaten,
    active_round.attack_limit,
    active_round.defense_started,
    active_round.take_declared,
    CASE
        WHEN g.game_status <> 'ACTIVE' OR viewer.player_status <> 'ACTIVE'
            THEN 'VIEW_ONLY'
        WHEN g.current_actor_seat_no <> viewer.seat_no
            THEN 'WAIT'
        WHEN g.phase = 'WAIT_ATTACK'
            THEN 'ATTACK'
        WHEN g.phase = 'WAIT_DEFENSE'
             AND viewer.seat_no = g.defender_seat_no
             AND g.game_variant = 'PEREVODNOY'
             AND NVL(active_round.defense_started, 'N') = 'N'
            THEN 'DEFEND,TRANSFER,TAKE'
        WHEN g.phase = 'WAIT_DEFENSE'
             AND viewer.seat_no = g.defender_seat_no
            THEN 'DEFEND,TAKE'
        WHEN g.phase IN ('WAIT_THROW', 'TAKE_THROW')
            THEN 'THROW_IN,PASS'
        ELSE 'WAIT'
    END AS allowed_actions,
    g.action_deadline_at
FROM session_player sp
JOIN durak_game_player viewer
  ON viewer.player_id = sp.player_id
JOIN durak_game g
  ON g.game_id = viewer.game_id
LEFT JOIN durak_round active_round
  ON active_round.game_id = g.game_id
 AND active_round.round_no = g.current_round_no
LEFT JOIN durak_table_pair pair_row
  ON pair_row.game_id = active_round.game_id
 AND pair_row.round_no = active_round.round_no
LEFT JOIN durak_card attack_card
  ON attack_card.card_id = pair_row.attack_card_id
LEFT JOIN durak_card defense_card
  ON defense_card.card_id = pair_row.defense_card_id
LEFT JOIN durak_game_player attacking_seat
  ON attacking_seat.game_id = pair_row.game_id
 AND attacking_seat.seat_no = pair_row.attacking_seat_no
LEFT JOIN durak_player attacking_player
  ON attacking_player.player_id = attacking_seat.player_id
LEFT JOIN durak_game_player defending_seat
  ON defending_seat.game_id = pair_row.game_id
 AND defending_seat.seat_no = pair_row.defending_seat_no
LEFT JOIN durak_player defending_player
  ON defending_player.player_id = defending_seat.player_id;

CREATE OR REPLACE VIEW v_hand_mine AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
)
SELECT
    gp.game_id,
    gp.seat_no,
    gc.received_seq,
    gc.card_id,
    c.card_code,
    c.rank_code,
    c.rank_value,
    c.suit_code,
    CASE WHEN c.suit_code = g.trump_suit THEN 'Y' ELSE 'N' END AS is_trump
FROM session_player sp
JOIN durak_game_player gp
  ON gp.player_id = sp.player_id
JOIN durak_game g
  ON g.game_id = gp.game_id
JOIN durak_game_card gc
  ON gc.game_id = gp.game_id
 AND gc.owner_seat_no = gp.seat_no
 AND gc.card_zone = 'HAND'
JOIN durak_card c
  ON c.card_id = gc.card_id;

CREATE OR REPLACE VIEW v_hand_public AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
)
SELECT
    listed.game_id,
    listed.seat_no,
    listed.player_id,
    p.display_name,
    p.player_type,
    listed.player_status,
    listed.hand_count,
    CASE WHEN listed.player_id = sp.player_id THEN 'MINE' ELSE 'HIDDEN' END
        AS hand_visibility
FROM session_player sp
JOIN durak_game_player viewer
  ON viewer.player_id = sp.player_id
JOIN durak_game_player listed
  ON listed.game_id = viewer.game_id
JOIN durak_player p
  ON p.player_id = listed.player_id;

CREATE OR REPLACE VIEW v_log AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
)
SELECT
    e.game_id,
    e.event_no,
    e.round_no,
    e.event_type,
    e.event_source,
    e.actor_seat_no,
    actor.display_name AS actor_name,
    e.target_seat_no,
    e.target_pair_no,
    c.card_code,
    e.phase_before,
    e.phase_after,
    e.event_message,
    e.created_at
FROM session_player sp
JOIN durak_game_player viewer
  ON viewer.player_id = sp.player_id
JOIN durak_event e
  ON e.game_id = viewer.game_id
LEFT JOIN durak_player actor
  ON actor.player_id = e.actor_player_id
LEFT JOIN durak_card c
  ON c.card_id = e.card_id
WHERE e.visibility_code = 'PUBLIC'
   OR (
       e.visibility_code = 'PRIVATE'
       AND e.visible_to_seat_no = viewer.seat_no
   );

CREATE OR REPLACE VIEW v_replay AS
WITH session_player AS (
    SELECT player_id
    FROM v_current_player
), replay_rows AS (
    SELECT
        e.game_id,
        e.event_no,
        e.event_id,
        e.round_no,
        e.event_type,
        e.event_source,
        e.actor_seat_no,
        actor.display_name AS actor_name,
        e.target_seat_no,
        e.target_pair_no,
        event_card.card_code AS event_card_code,
        cm.card_move_id,
        move_card.card_code AS moved_card_code,
        cm.from_zone,
        cm.to_zone,
        cm.from_owner_seat_no,
        cm.to_owner_seat_no,
        cm.from_pair_no,
        cm.to_pair_no,
        cm.is_face_up_after,
        e.phase_before,
        e.phase_after,
        e.event_message,
        e.created_at
    FROM session_player sp
    JOIN durak_game_player viewer
      ON viewer.player_id = sp.player_id
    JOIN durak_game g
      ON g.game_id = viewer.game_id
    JOIN durak_event e
      ON e.game_id = g.game_id
    LEFT JOIN durak_player actor
      ON actor.player_id = e.actor_player_id
    LEFT JOIN durak_card event_card
      ON event_card.card_id = e.card_id
    LEFT JOIN durak_card_move cm
      ON cm.game_id = e.game_id
     AND cm.event_id = e.event_id
    LEFT JOIN durak_card move_card
      ON move_card.card_id = cm.card_id
    WHERE g.game_status IN ('FINISHED', 'CANCELLED', 'EXPIRED')
       OR e.visibility_code = 'PUBLIC'
       OR (
           e.visibility_code = 'PRIVATE'
           AND e.visible_to_seat_no = viewer.seat_no
       )
)
SELECT
    ROW_NUMBER() OVER (
        PARTITION BY game_id
        ORDER BY event_no, card_move_id NULLS FIRST
    ) AS replay_step_no,
    game_id,
    event_id,
    event_no,
    card_move_id,
    round_no,
    event_type,
    event_source,
    actor_seat_no,
    actor_name,
    target_seat_no,
    target_pair_no,
    event_card_code,
    moved_card_code,
    from_zone,
    to_zone,
    from_owner_seat_no,
    to_owner_seat_no,
    from_pair_no,
    to_pair_no,
    is_face_up_after,
    phase_before,
    phase_after,
    event_message,
    created_at
FROM replay_rows;

CREATE OR REPLACE VIEW v_analytics AS
WITH event_stats AS (
    SELECT
        game_id,
        COUNT(*) AS events_count,
        SUM(
            CASE
                WHEN event_type IN (
                    'ATTACK', 'DEFEND', 'THROW_IN', 'TRANSFER',
                    'PASS', 'TAKE_DECLARED'
                ) THEN 1
                ELSE 0
            END
        ) AS actions_count,
        SUM(CASE WHEN event_type = 'ATTACK' THEN 1 ELSE 0 END) AS attacks_count,
        SUM(CASE WHEN event_type = 'DEFEND' THEN 1 ELSE 0 END) AS defenses_count,
        SUM(CASE WHEN event_type = 'THROW_IN' THEN 1 ELSE 0 END) AS throw_ins_count,
        SUM(CASE WHEN event_type = 'TRANSFER' THEN 1 ELSE 0 END) AS transfers_count,
        SUM(CASE WHEN event_type = 'TAKE_DECLARED' THEN 1 ELSE 0 END) AS takes_count,
        SUM(CASE WHEN event_type = 'PLAYER_OUT' THEN 1 ELSE 0 END) AS exits_count,
        ROUND(AVG(CASE WHEN event_type = 'PLAYER_OUT' THEN round_no END), 2)
            AS avg_round_to_exit
    FROM durak_event
    GROUP BY game_id
), round_stats AS (
    SELECT
        game_id,
        COUNT(*) AS rounds_count,
        SUM(CASE WHEN round_status = 'DEFENDED' THEN 1 ELSE 0 END)
            AS defended_rounds_count,
        SUM(CASE WHEN round_status = 'TAKEN' THEN 1 ELSE 0 END)
            AS taken_rounds_count
    FROM durak_round
    GROUP BY game_id
), bot_stats AS (
    SELECT
        game_id,
        COUNT(*) AS bot_decisions_count,
        ROUND(AVG(duration_ms), 2) AS avg_bot_duration_ms,
        MAX(duration_ms) AS max_bot_duration_ms
    FROM durak_bot_decision
    GROUP BY game_id
), player_stats AS (
    SELECT game_id, COUNT(*) AS players_count
    FROM durak_game_player
    GROUP BY game_id
)
SELECT
    g.game_id,
    g.daily_id,
    g.game_status,
    g.deck_size,
    g.game_variant,
    NVL(ps.players_count, 0) AS players_count,
    NVL(rs.rounds_count, 0) AS rounds_count,
    NVL(es.events_count, 0) AS events_count,
    NVL(es.actions_count, 0) AS actions_count,
    NVL(es.attacks_count, 0) AS attacks_count,
    NVL(es.defenses_count, 0) AS defenses_count,
    NVL(es.throw_ins_count, 0) AS throw_ins_count,
    NVL(es.transfers_count, 0) AS transfers_count,
    NVL(es.takes_count, 0) AS takes_count,
    NVL(rs.defended_rounds_count, 0) AS defended_rounds_count,
    NVL(rs.taken_rounds_count, 0) AS taken_rounds_count,
    CASE
        WHEN NVL(rs.rounds_count, 0) = 0 THEN 0
        ELSE ROUND(NVL(rs.taken_rounds_count, 0) / rs.rounds_count, 4)
    END AS take_share,
    NVL(es.exits_count, 0) AS exits_count,
    es.avg_round_to_exit,
    NVL(bs.bot_decisions_count, 0) AS bot_decisions_count,
    NVL(bs.avg_bot_duration_ms, 0) AS avg_bot_duration_ms,
    NVL(bs.max_bot_duration_ms, 0) AS max_bot_duration_ms,
    g.started_at,
    g.finished_at
FROM durak_game g
LEFT JOIN event_stats es
  ON es.game_id = g.game_id
LEFT JOIN round_stats rs
  ON rs.game_id = g.game_id
LEFT JOIN bot_stats bs
  ON bs.game_id = g.game_id
LEFT JOIN player_stats ps
  ON ps.game_id = g.game_id;

CREATE OR REPLACE VIEW v_leaderboard AS
WITH finished_game AS (
    SELECT
        gp.player_id,
        gp.result_code,
        g.game_id,
        g.current_round_no,
        CASE
            WHEN g.started_at IS NOT NULL AND g.finished_at IS NOT NULL THEN
                EXTRACT(DAY FROM (g.finished_at - g.started_at)) * 86400
                + EXTRACT(HOUR FROM (g.finished_at - g.started_at)) * 3600
                + EXTRACT(MINUTE FROM (g.finished_at - g.started_at)) * 60
                + EXTRACT(SECOND FROM (g.finished_at - g.started_at))
        END AS duration_sec
    FROM durak_game_player gp
    JOIN durak_game g
      ON g.game_id = gp.game_id
     AND g.game_status = 'FINISHED'
)
SELECT
    p.player_id,
    p.display_name,
    p.player_type,
    COUNT(fg.game_id) AS games_played,
    SUM(CASE WHEN fg.result_code = 'WIN' THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN fg.result_code = 'LOSS' THEN 1 ELSE 0 END) AS losses,
    SUM(CASE WHEN fg.result_code = 'DRAW' THEN 1 ELSE 0 END) AS draws,
    ROUND(AVG(fg.duration_sec), 2) AS avg_duration_sec,
    ROUND(AVG(fg.current_round_no), 2) AS avg_rounds
FROM durak_player p
LEFT JOIN finished_game fg
  ON fg.player_id = p.player_id
GROUP BY p.player_id, p.display_name, p.player_type;

CREATE OR REPLACE VIEW v_daily AS
SELECT
    d.daily_id,
    d.daily_date,
    d.deck_size,
    d.game_variant,
    d.first_move_mode,
    d.rules_version,
    COUNT(DISTINCT r.game_id) AS completed_games,
    COUNT(r.daily_result_id) AS recorded_results,
    MIN(d.created_at) AS created_at
FROM durak_daily d
LEFT JOIN durak_daily_result r
  ON r.daily_id = d.daily_id
GROUP BY
    d.daily_id,
    d.daily_date,
    d.deck_size,
    d.game_variant,
    d.first_move_mode,
    d.rules_version;

CREATE OR REPLACE VIEW v_daily_results AS
SELECT
    d.daily_date,
    d.daily_id,
    r.game_id,
    r.player_id,
    p.display_name,
    r.result_code,
    r.finish_place,
    r.rounds_played,
    r.actions_count,
    r.duration_sec,
    DENSE_RANK() OVER (
        PARTITION BY r.daily_id
        ORDER BY
            CASE r.result_code WHEN 'WIN' THEN 1 WHEN 'DRAW' THEN 2 ELSE 3 END,
            r.finish_place NULLS LAST,
            r.rounds_played,
            r.duration_sec,
            r.actions_count
    ) AS daily_place,
    r.recorded_at
FROM durak_daily_result r
JOIN durak_daily d
  ON d.daily_id = r.daily_id
JOIN durak_player p
  ON p.player_id = r.player_id;

CREATE OR REPLACE VIEW v_tournament AS
SELECT
    t.tournament_id,
    t.tournament_name,
    t.tournament_format,
    t.tournament_status,
    tournament_creator.display_name AS created_by,
    t.deck_size,
    t.game_variant,
    t.first_move_mode,
    t.max_pairs,
    t.turn_timeout_sec,
    t.idle_timeout_min,
    (
        SELECT COUNT(*)
        FROM durak_tournament_player participant
        WHERE participant.tournament_id = t.tournament_id
    ) AS player_count,
    m.tournament_round_no,
    m.match_no,
    m.match_status,
    m.tournament_match_id,
    m.game_id,
    m.player1_id,
    player1.display_name AS player1_name,
    m.player2_id,
    player2.display_name AS player2_name,
    m.winner_player_id,
    winner.display_name AS winner_name,
    m.result_reason,
    champion.display_name AS champion_name,
    t.finish_reason,
    t.created_at,
    t.started_at,
    t.finished_at
FROM durak_tournament t
JOIN durak_player tournament_creator
  ON tournament_creator.player_id = t.created_by_player_id
LEFT JOIN durak_tournament_match m
  ON m.tournament_id = t.tournament_id
LEFT JOIN durak_player player1
  ON player1.player_id = m.player1_id
LEFT JOIN durak_player player2
  ON player2.player_id = m.player2_id
LEFT JOIN durak_player winner
  ON winner.player_id = m.winner_player_id
LEFT JOIN durak_player champion
  ON champion.player_id = t.champion_player_id;

CREATE OR REPLACE VIEW v_tournament_standings AS
SELECT
    tp.tournament_id,
    t.tournament_name,
    t.tournament_format,
    t.tournament_status,
    tp.player_id,
    p.display_name,
    p.player_type,
    p.bot_level,
    tp.seed_no,
    tp.player_status,
    tp.points,
    tp.wins_count,
    tp.losses_count,
    tp.draws_count,
    DENSE_RANK() OVER (
        PARTITION BY tp.tournament_id
        ORDER BY
            tp.points DESC,
            tp.wins_count DESC,
            tp.draws_count DESC,
            tp.seed_no NULLS LAST
    ) AS standing_place,
    tp.joined_at
FROM durak_tournament_player tp
JOIN durak_tournament t
  ON t.tournament_id = tp.tournament_id
JOIN durak_player p
  ON p.player_id = tp.player_id;

CREATE OR REPLACE VIEW v_errors AS
SELECT
    e.error_id,
    e.game_id,
    e.action_type,
    e.error_code,
    e.error_message,
    e.created_at
FROM durak_error e
WHERE e.db_username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'))
   OR e.player_id IN (
       SELECT player_id
       FROM v_current_player
   );

PROMPT Защищённые представления проекта DURAK созданы
