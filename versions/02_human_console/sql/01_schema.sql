PROMPT Создание последовательности и таблиц проекта DURAK

CREATE SEQUENCE durak_id_seq
    START WITH 1000
    INCREMENT BY 1
    CACHE 100
    NOCYCLE;

CREATE TABLE durak_player (
    player_id       NUMBER(19)    CONSTRAINT pk_dp PRIMARY KEY,
    db_username     VARCHAR2(128),
    display_name    VARCHAR2(100) NOT NULL,
    player_type     VARCHAR2(10)  DEFAULT 'HUMAN' NOT NULL,
    bot_level       VARCHAR2(10),
    locale_code     VARCHAR2(20)  DEFAULT 'ru-RU' NOT NULL,
    time_zone_name  VARCHAR2(64)  DEFAULT 'Europe/Moscow' NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT uq_dp_username UNIQUE (db_username),
    CONSTRAINT ck_dp_type CHECK (player_type IN ('HUMAN', 'BOT')),
    CONSTRAINT ck_dp_bot_level CHECK (
        (player_type = 'HUMAN' AND db_username IS NOT NULL AND bot_level IS NULL)
        OR
        (player_type = 'BOT' AND db_username IS NULL
         AND bot_level IN ('EASY', 'NORMAL', 'HARD'))
    ),
    CONSTRAINT ck_dp_username_case CHECK (
        db_username IS NULL OR db_username = UPPER(db_username)
    )
);

CREATE TABLE durak_card (
    card_id          NUMBER(3)    CONSTRAINT pk_dc PRIMARY KEY,
    card_code        VARCHAR2(3)  NOT NULL,
    rank_code        VARCHAR2(2)  NOT NULL,
    rank_value       NUMBER(2)    NOT NULL,
    suit_code        CHAR(1)      NOT NULL,
    included_in_36   CHAR(1)      NOT NULL,
    sort_order       NUMBER(3)    NOT NULL,
    CONSTRAINT uq_dc_code UNIQUE (card_code),
    CONSTRAINT uq_dc_rank_suit UNIQUE (rank_value, suit_code),
    CONSTRAINT uq_dc_sort UNIQUE (sort_order),
    CONSTRAINT ck_dc_rank_value CHECK (rank_value BETWEEN 2 AND 14),
    CONSTRAINT ck_dc_suit CHECK (suit_code IN ('C', 'D', 'H', 'S')),
    CONSTRAINT ck_dc_deck36 CHECK (included_in_36 IN ('Y', 'N'))
);

CREATE TABLE durak_daily (
    daily_id          NUMBER(19)   CONSTRAINT pk_dd PRIMARY KEY,
    daily_date        DATE         NOT NULL,
    deck_size         NUMBER(2)    NOT NULL,
    game_variant      VARCHAR2(12) NOT NULL,
    first_move_mode   VARCHAR2(20) NOT NULL,
    seed_text         VARCHAR2(128) NOT NULL,
    config_hash       RAW(32)      NOT NULL,
    rules_version     VARCHAR2(20) NOT NULL,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT uq_dd_config UNIQUE (
        daily_date, deck_size, game_variant, first_move_mode, rules_version
    ),
    CONSTRAINT ck_dd_date CHECK (daily_date = TRUNC(daily_date)),
    CONSTRAINT ck_dd_deck CHECK (deck_size IN (36, 52)),
    CONSTRAINT ck_dd_variant CHECK (game_variant IN ('PODKIDNOY', 'PEREVODNOY')),
    CONSTRAINT ck_dd_first CHECK (
        first_move_mode IN ('LOWEST_TRUMP', 'SEEDED_RANDOM')
    )
);

CREATE TABLE durak_game (
    game_id                  NUMBER(19)    CONSTRAINT pk_dg PRIMARY KEY,
    created_by_player_id     NUMBER(19)    NOT NULL,
    daily_id                 NUMBER(19),
    deck_size                NUMBER(2)     DEFAULT 36 NOT NULL,
    game_variant             VARCHAR2(12)  DEFAULT 'PODKIDNOY' NOT NULL,
    first_move_mode          VARCHAR2(20)  DEFAULT 'LOWEST_TRUMP' NOT NULL,
    target_hand_size         NUMBER(2)     DEFAULT 6 NOT NULL,
    max_pairs                NUMBER(2)     NOT NULL,
    allow_throw_after_take   CHAR(1)       DEFAULT 'N' NOT NULL,
    limit_by_defender_hand   CHAR(1)       DEFAULT 'Y' NOT NULL,
    turn_timeout_sec         NUMBER(6)     DEFAULT 60 NOT NULL,
    idle_timeout_min         NUMBER(6)     DEFAULT 30 NOT NULL,
    seed_text                VARCHAR2(128) NOT NULL,
    seed_hash                RAW(32)       NOT NULL,
    shuffle_version          VARCHAR2(20)  DEFAULT 'SHA256-V1' NOT NULL,
    game_status              VARCHAR2(12)  DEFAULT 'LOBBY' NOT NULL,
    phase                    VARCHAR2(20)  DEFAULT 'LOBBY' NOT NULL,
    trump_suit               CHAR(1),
    trump_card_id            NUMBER(3),
    current_round_no         NUMBER(10)    DEFAULT 0 NOT NULL,
    attacker_seat_no         NUMBER(1),
    defender_seat_no         NUMBER(1),
    current_actor_seat_no    NUMBER(1),
    version_no               NUMBER(19)    DEFAULT 0 NOT NULL,
    next_event_no            NUMBER(19)    DEFAULT 1 NOT NULL,
    action_deadline_at       TIMESTAMP WITH TIME ZONE,
    last_activity_at         TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    created_at               TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    started_at               TIMESTAMP WITH TIME ZONE,
    finished_at              TIMESTAMP WITH TIME ZONE,
    fool_seat_no             NUMBER(1),
    finish_reason            VARCHAR2(40),
    CONSTRAINT fk_dg_creator FOREIGN KEY (created_by_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_dg_daily FOREIGN KEY (daily_id)
        REFERENCES durak_daily(daily_id),
    CONSTRAINT fk_dg_trump FOREIGN KEY (trump_card_id)
        REFERENCES durak_card(card_id),
    CONSTRAINT ck_dg_deck CHECK (deck_size IN (36, 52)),
    CONSTRAINT ck_dg_variant CHECK (game_variant IN ('PODKIDNOY', 'PEREVODNOY')),
    CONSTRAINT ck_dg_first CHECK (
        first_move_mode IN ('LOWEST_TRUMP', 'SEEDED_RANDOM')
    ),
    CONSTRAINT ck_dg_hand_size CHECK (target_hand_size BETWEEN 1 AND 12),
    CONSTRAINT ck_dg_max_pairs CHECK (
        max_pairs BETWEEN 1 AND
            CASE deck_size WHEN 36 THEN 6 WHEN 52 THEN 8 END
    ),
    CONSTRAINT ck_dg_throw_take CHECK (allow_throw_after_take IN ('Y', 'N')),
    CONSTRAINT ck_dg_limit_hand CHECK (limit_by_defender_hand IN ('Y', 'N')),
    CONSTRAINT ck_dg_turn_timeout CHECK (turn_timeout_sec BETWEEN 0 AND 86400),
    CONSTRAINT ck_dg_idle_timeout CHECK (idle_timeout_min BETWEEN 1 AND 10080),
    CONSTRAINT ck_dg_status CHECK (
        game_status IN ('LOBBY', 'ACTIVE', 'FINISHED', 'CANCELLED', 'EXPIRED')
    ),
    CONSTRAINT ck_dg_phase CHECK (
        phase IN (
            'LOBBY', 'WAIT_ATTACK', 'WAIT_DEFENSE', 'WAIT_THROW',
            'TAKE_THROW', 'ROUND_RESOLVE', 'FINISHED'
        )
    ),
    CONSTRAINT ck_dg_status_phase CHECK (
        (game_status = 'LOBBY' AND phase = 'LOBBY')
        OR (game_status = 'ACTIVE' AND phase IN (
            'WAIT_ATTACK', 'WAIT_DEFENSE', 'WAIT_THROW',
            'TAKE_THROW', 'ROUND_RESOLVE'
        ))
        OR (game_status IN ('FINISHED', 'CANCELLED', 'EXPIRED')
            AND phase = 'FINISHED')
    ),
    CONSTRAINT ck_dg_trump_suit CHECK (
        trump_suit IS NULL OR trump_suit IN ('C', 'D', 'H', 'S')
    ),
    CONSTRAINT ck_dg_attacker CHECK (
        attacker_seat_no IS NULL OR attacker_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dg_defender CHECK (
        defender_seat_no IS NULL OR defender_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dg_actor CHECK (
        current_actor_seat_no IS NULL OR current_actor_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dg_fool CHECK (
        fool_seat_no IS NULL OR fool_seat_no BETWEEN 1 AND 6
    )
);

CREATE TABLE durak_game_player (
    game_id          NUMBER(19)   NOT NULL,
    seat_no          NUMBER(1)    NOT NULL,
    player_id        NUMBER(19)   NOT NULL,
    player_status    VARCHAR2(10) DEFAULT 'WAITING' NOT NULL,
    is_creator       CHAR(1)      DEFAULT 'N' NOT NULL,
    hand_count       NUMBER(3)    DEFAULT 0 NOT NULL,
    finish_place     NUMBER(1),
    result_code      VARCHAR2(12),
    joined_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    exited_at        TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_dgp PRIMARY KEY (game_id, seat_no),
    CONSTRAINT uq_dgp_player UNIQUE (game_id, player_id),
    CONSTRAINT fk_dgp_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_dgp_player FOREIGN KEY (player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_dgp_seat CHECK (seat_no BETWEEN 1 AND 6),
    CONSTRAINT ck_dgp_status CHECK (
        player_status IN ('WAITING', 'ACTIVE', 'OUT', 'FOOL', 'LEFT')
    ),
    CONSTRAINT ck_dgp_creator CHECK (is_creator IN ('Y', 'N')),
    CONSTRAINT ck_dgp_hand_count CHECK (hand_count >= 0),
    CONSTRAINT ck_dgp_place CHECK (
        finish_place IS NULL OR finish_place BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dgp_result CHECK (
        result_code IS NULL OR result_code IN ('WIN', 'LOSS', 'DRAW', 'ABANDONED')
    )
);

CREATE UNIQUE INDEX ux_dgp_creator
    ON durak_game_player (
        CASE WHEN is_creator = 'Y' THEN game_id END
    );

CREATE TABLE durak_active_session (
    player_id        NUMBER(19) CONSTRAINT pk_das PRIMARY KEY,
    game_id          NUMBER(19) NOT NULL,
    opened_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_das_player FOREIGN KEY (player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_das_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id)
);

CREATE TABLE durak_game_card (
    game_id          NUMBER(19)  NOT NULL,
    card_id          NUMBER(3)   NOT NULL,
    deck_pos         NUMBER(3)   NOT NULL,
    card_zone        VARCHAR2(10) NOT NULL,
    owner_seat_no    NUMBER(1),
    table_pair_no    NUMBER(2),
    received_seq     NUMBER(19),
    is_face_up       CHAR(1)     DEFAULT 'N' NOT NULL,
    changed_at       TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_dgc PRIMARY KEY (game_id, card_id),
    CONSTRAINT uq_dgc_deck_pos UNIQUE (game_id, deck_pos),
    CONSTRAINT fk_dgc_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_dgc_card FOREIGN KEY (card_id)
        REFERENCES durak_card(card_id),
    CONSTRAINT fk_dgc_owner FOREIGN KEY (game_id, owner_seat_no)
        REFERENCES durak_game_player(game_id, seat_no),
    CONSTRAINT ck_dgc_deck_pos CHECK (deck_pos BETWEEN 1 AND 52),
    CONSTRAINT ck_dgc_zone CHECK (
        card_zone IN ('TALON', 'HAND', 'ATTACK', 'DEFENSE', 'DISCARD')
    ),
    CONSTRAINT ck_dgc_face CHECK (is_face_up IN ('Y', 'N')),
    CONSTRAINT ck_dgc_location CHECK (
        (card_zone = 'HAND' AND owner_seat_no IS NOT NULL AND table_pair_no IS NULL)
        OR
        (card_zone IN ('ATTACK', 'DEFENSE')
         AND owner_seat_no IS NULL AND table_pair_no IS NOT NULL)
        OR
        (card_zone IN ('TALON', 'DISCARD')
         AND owner_seat_no IS NULL AND table_pair_no IS NULL)
    )
);

CREATE TABLE durak_round (
    game_id                    NUMBER(19)  NOT NULL,
    round_no                   NUMBER(10)  NOT NULL,
    round_status               VARCHAR2(12) DEFAULT 'ACTIVE' NOT NULL,
    primary_attacker_seat_no   NUMBER(1)   NOT NULL,
    initial_defender_seat_no   NUMBER(1)   NOT NULL,
    defender_seat_no           NUMBER(1)   NOT NULL,
    throw_cursor_seat_no       NUMBER(1),
    next_attacker_seat_no      NUMBER(1),
    defender_hand_at_start     NUMBER(3)   NOT NULL,
    attack_limit               NUMBER(2)   NOT NULL,
    consecutive_passes         NUMBER(2)   DEFAULT 0 NOT NULL,
    transfer_count             NUMBER(2)   DEFAULT 0 NOT NULL,
    defense_started            CHAR(1)     DEFAULT 'N' NOT NULL,
    take_declared              CHAR(1)     DEFAULT 'N' NOT NULL,
    outcome_reason             VARCHAR2(100),
    started_at                 TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    ended_at                   TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_dr PRIMARY KEY (game_id, round_no),
    CONSTRAINT fk_dr_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT ck_dr_no CHECK (round_no > 0),
    CONSTRAINT ck_dr_status CHECK (
        round_status IN ('ACTIVE', 'DEFENDED', 'TAKEN', 'CANCELLED')
    ),
    CONSTRAINT ck_dr_seats CHECK (
        primary_attacker_seat_no BETWEEN 1 AND 6
        AND initial_defender_seat_no BETWEEN 1 AND 6
        AND defender_seat_no BETWEEN 1 AND 6
        AND (throw_cursor_seat_no IS NULL OR throw_cursor_seat_no BETWEEN 1 AND 6)
        AND (next_attacker_seat_no IS NULL OR next_attacker_seat_no BETWEEN 1 AND 6)
    ),
    CONSTRAINT ck_dr_hand CHECK (defender_hand_at_start >= 0),
    CONSTRAINT ck_dr_limit CHECK (attack_limit BETWEEN 1 AND 8),
    CONSTRAINT ck_dr_passes CHECK (consecutive_passes >= 0),
    CONSTRAINT ck_dr_transfers CHECK (transfer_count >= 0),
    CONSTRAINT ck_dr_def_started CHECK (defense_started IN ('Y', 'N')),
    CONSTRAINT ck_dr_take CHECK (take_declared IN ('Y', 'N'))
);

CREATE TABLE durak_table_pair (
    game_id             NUMBER(19) NOT NULL,
    round_no            NUMBER(10) NOT NULL,
    pair_no             NUMBER(2)  NOT NULL,
    attack_card_id      NUMBER(3)  NOT NULL,
    attacking_seat_no   NUMBER(1)  NOT NULL,
    defense_card_id     NUMBER(3),
    defending_seat_no   NUMBER(1),
    pair_status         VARCHAR2(10) DEFAULT 'OPEN' NOT NULL,
    attack_event_no     NUMBER(19) NOT NULL,
    defense_event_no    NUMBER(19),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    covered_at          TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_dtp PRIMARY KEY (game_id, round_no, pair_no),
    CONSTRAINT uq_dtp_attack UNIQUE (game_id, round_no, attack_card_id),
    CONSTRAINT fk_dtp_round FOREIGN KEY (game_id, round_no)
        REFERENCES durak_round(game_id, round_no),
    CONSTRAINT fk_dtp_attack_card FOREIGN KEY (game_id, attack_card_id)
        REFERENCES durak_game_card(game_id, card_id),
    CONSTRAINT fk_dtp_def_card FOREIGN KEY (game_id, defense_card_id)
        REFERENCES durak_game_card(game_id, card_id),
    CONSTRAINT ck_dtp_pair_no CHECK (pair_no BETWEEN 1 AND 8),
    CONSTRAINT ck_dtp_attack_seat CHECK (attacking_seat_no BETWEEN 1 AND 6),
    CONSTRAINT ck_dtp_def_seat CHECK (
        defending_seat_no IS NULL OR defending_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dtp_status CHECK (
        pair_status IN ('OPEN', 'COVERED', 'TAKEN', 'DISCARDED')
    ),
    CONSTRAINT ck_dtp_defense CHECK (
        (pair_status = 'OPEN' AND defense_card_id IS NULL
         AND defending_seat_no IS NULL AND defense_event_no IS NULL)
        OR
        (pair_status IN ('COVERED', 'DISCARDED')
         AND defense_card_id IS NOT NULL AND defending_seat_no IS NOT NULL)
        OR
        (pair_status = 'TAKEN')
    )
);

CREATE TABLE durak_event (
    event_id            NUMBER(19)   CONSTRAINT pk_de PRIMARY KEY,
    game_id             NUMBER(19)   NOT NULL,
    event_no            NUMBER(19)   NOT NULL,
    round_no            NUMBER(10),
    event_type          VARCHAR2(30) NOT NULL,
    event_source        VARCHAR2(10) NOT NULL,
    actor_player_id     NUMBER(19),
    actor_seat_no       NUMBER(1),
    card_id             NUMBER(3),
    target_pair_no      NUMBER(2),
    target_seat_no      NUMBER(1),
    phase_before        VARCHAR2(20),
    phase_after         VARCHAR2(20),
    version_before      NUMBER(19),
    version_after       NUMBER(19),
    visibility_code     VARCHAR2(10) DEFAULT 'PUBLIC' NOT NULL,
    visible_to_seat_no  NUMBER(1),
    event_message       VARCHAR2(1000) NOT NULL,
    event_payload       CLOB,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT uq_de_game_no UNIQUE (game_id, event_no),
    CONSTRAINT uq_de_game_event UNIQUE (game_id, event_id),
    CONSTRAINT fk_de_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_de_player FOREIGN KEY (actor_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_de_card FOREIGN KEY (card_id)
        REFERENCES durak_card(card_id),
    CONSTRAINT ck_de_no CHECK (event_no > 0),
    CONSTRAINT ck_de_source CHECK (
        event_source IN ('MANUAL', 'SYSTEM', 'TIMEOUT', 'BOT', 'ADMIN')
    ),
    CONSTRAINT ck_de_type CHECK (
        event_type IN (
            'GAME_CREATED', 'PLAYER_JOINED', 'BOT_ADDED', 'GAME_STARTED',
            'SHUFFLED', 'DEALT', 'ROUND_STARTED', 'ATTACK', 'THROW_IN',
            'DEFEND', 'TRANSFER', 'PASS', 'TAKE_DECLARED', 'TAKE',
            'DISCARD', 'DRAW', 'PLAYER_OUT', 'GAME_FINISHED',
            'GAME_CANCELLED', 'TIMEOUT', 'IDLE_TIMEOUT',
            'BOT_DECISION', 'HEARTBEAT'
        )
    ),
    CONSTRAINT ck_de_actor_seat CHECK (
        actor_seat_no IS NULL OR actor_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_de_target_seat CHECK (
        target_seat_no IS NULL OR target_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_de_visible CHECK (
        visibility_code IN ('PUBLIC', 'PRIVATE', 'SYSTEM')
    ),
    CONSTRAINT ck_de_visible_seat CHECK (
        visible_to_seat_no IS NULL OR visible_to_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_de_payload CHECK (event_payload IS JSON)
);

CREATE TABLE durak_card_move (
    card_move_id        NUMBER(19) CONSTRAINT pk_dcm PRIMARY KEY,
    game_id             NUMBER(19) NOT NULL,
    event_id            NUMBER(19) NOT NULL,
    card_id             NUMBER(3)  NOT NULL,
    from_zone           VARCHAR2(10),
    to_zone             VARCHAR2(10) NOT NULL,
    from_owner_seat_no  NUMBER(1),
    to_owner_seat_no    NUMBER(1),
    from_pair_no        NUMBER(2),
    to_pair_no          NUMBER(2),
    is_face_up_after    CHAR(1) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_dcm_event FOREIGN KEY (game_id, event_id)
        REFERENCES durak_event(game_id, event_id),
    CONSTRAINT fk_dcm_card FOREIGN KEY (game_id, card_id)
        REFERENCES durak_game_card(game_id, card_id),
    CONSTRAINT ck_dcm_from_zone CHECK (
        from_zone IS NULL OR from_zone IN ('TALON', 'HAND', 'ATTACK', 'DEFENSE', 'DISCARD')
    ),
    CONSTRAINT ck_dcm_to_zone CHECK (
        to_zone IN ('TALON', 'HAND', 'ATTACK', 'DEFENSE', 'DISCARD')
    ),
    CONSTRAINT ck_dcm_face CHECK (is_face_up_after IN ('Y', 'N')),
    CONSTRAINT ck_dcm_from_seat CHECK (
        from_owner_seat_no IS NULL OR from_owner_seat_no BETWEEN 1 AND 6
    ),
    CONSTRAINT ck_dcm_to_seat CHECK (
        to_owner_seat_no IS NULL OR to_owner_seat_no BETWEEN 1 AND 6
    )
);

CREATE TABLE durak_error (
    error_id          NUMBER(19) CONSTRAINT pk_der PRIMARY KEY,
    game_id           NUMBER(19),
    player_id         NUMBER(19),
    db_username       VARCHAR2(128),
    action_type       VARCHAR2(30) NOT NULL,
    error_code        NUMBER(10) NOT NULL,
    error_message     VARCHAR2(1000) NOT NULL,
    error_payload     CLOB,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT ck_der_payload CHECK (error_payload IS JSON)
);

COMMENT ON TABLE durak_error IS
    'Автономный журнал отказов; внешние ключи намеренно отсутствуют, чтобы логирование не зависело от основной транзакции.';

CREATE TABLE durak_daily_result (
    daily_result_id NUMBER(19) CONSTRAINT pk_ddr PRIMARY KEY,
    daily_id        NUMBER(19) NOT NULL,
    game_id         NUMBER(19) NOT NULL,
    player_id       NUMBER(19) NOT NULL,
    result_code     VARCHAR2(12) NOT NULL,
    finish_place    NUMBER(1),
    rounds_played   NUMBER(10) NOT NULL,
    actions_count   NUMBER(19) NOT NULL,
    duration_sec    NUMBER(19) NOT NULL,
    recorded_at     TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT uq_ddr_result UNIQUE (daily_id, game_id, player_id),
    CONSTRAINT fk_ddr_daily FOREIGN KEY (daily_id)
        REFERENCES durak_daily(daily_id),
    CONSTRAINT fk_ddr_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_ddr_player FOREIGN KEY (player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_ddr_result CHECK (result_code IN ('WIN', 'LOSS', 'DRAW')),
    CONSTRAINT ck_ddr_values CHECK (
        rounds_played >= 0 AND actions_count >= 0 AND duration_sec >= 0
    )
);

CREATE TABLE durak_bot_decision (
    decision_id       NUMBER(19) CONSTRAINT pk_dbd PRIMARY KEY,
    game_id           NUMBER(19) NOT NULL,
    event_id          NUMBER(19),
    bot_player_id     NUMBER(19) NOT NULL,
    bot_level         VARCHAR2(10) NOT NULL,
    selected_action   VARCHAR2(30) NOT NULL,
    score_value       NUMBER,
    duration_ms       NUMBER(19) NOT NULL,
    explanation       VARCHAR2(1000),
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_dbd_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_dbd_event FOREIGN KEY (event_id)
        REFERENCES durak_event(event_id),
    CONSTRAINT fk_dbd_player FOREIGN KEY (bot_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_dbd_level CHECK (bot_level IN ('EASY', 'NORMAL', 'HARD')),
    CONSTRAINT ck_dbd_duration CHECK (duration_ms >= 0)
);

CREATE TABLE durak_tournament (
    tournament_id        NUMBER(19) CONSTRAINT pk_dt PRIMARY KEY,
    tournament_name      VARCHAR2(100) NOT NULL,
    created_by_player_id NUMBER(19) NOT NULL,
    tournament_format    VARCHAR2(20) DEFAULT 'ROUND_ROBIN' NOT NULL,
    deck_size             NUMBER(2) DEFAULT 36 NOT NULL,
    game_variant          VARCHAR2(12) DEFAULT 'PODKIDNOY' NOT NULL,
    first_move_mode       VARCHAR2(20) DEFAULT 'LOWEST_TRUMP' NOT NULL,
    max_pairs             NUMBER(2) NOT NULL,
    allow_throw_after_take CHAR(1) DEFAULT 'N' NOT NULL,
    limit_by_defender_hand CHAR(1) DEFAULT 'Y' NOT NULL,
    turn_timeout_sec      NUMBER(6) DEFAULT 60 NOT NULL,
    idle_timeout_min      NUMBER(6) DEFAULT 30 NOT NULL,
    seed_text             VARCHAR2(128) NOT NULL,
    seed_hash             RAW(32) NOT NULL,
    tournament_status    VARCHAR2(12) DEFAULT 'LOBBY' NOT NULL,
    champion_player_id   NUMBER(19),
    finish_reason         VARCHAR2(40),
    created_at           TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    started_at           TIMESTAMP WITH TIME ZONE,
    finished_at          TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_dt_creator FOREIGN KEY (created_by_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_dt_champion FOREIGN KEY (champion_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_dt_format CHECK (
        tournament_format IN ('ROUND_ROBIN', 'SINGLE_ELIMINATION')
    ),
    CONSTRAINT ck_dt_deck CHECK (deck_size IN (36, 52)),
    CONSTRAINT ck_dt_variant CHECK (
        game_variant IN ('PODKIDNOY', 'PEREVODNOY')
    ),
    CONSTRAINT ck_dt_first CHECK (
        first_move_mode IN ('LOWEST_TRUMP', 'SEEDED_RANDOM')
    ),
    CONSTRAINT ck_dt_max_pairs CHECK (
        max_pairs BETWEEN 1 AND
            CASE deck_size WHEN 36 THEN 6 WHEN 52 THEN 8 END
    ),
    CONSTRAINT ck_dt_throw_take CHECK (allow_throw_after_take IN ('Y', 'N')),
    CONSTRAINT ck_dt_limit_hand CHECK (limit_by_defender_hand IN ('Y', 'N')),
    CONSTRAINT ck_dt_turn_timeout CHECK (turn_timeout_sec BETWEEN 0 AND 86400),
    CONSTRAINT ck_dt_idle_timeout CHECK (idle_timeout_min BETWEEN 1 AND 10080),
    CONSTRAINT ck_dt_status CHECK (
        tournament_status IN ('LOBBY', 'ACTIVE', 'FINISHED', 'CANCELLED')
    )
);

CREATE TABLE durak_tournament_player (
    tournament_id NUMBER(19) NOT NULL,
    player_id     NUMBER(19) NOT NULL,
    seed_no       NUMBER(6),
    player_status VARCHAR2(12) DEFAULT 'REGISTERED' NOT NULL,
    points        NUMBER DEFAULT 0 NOT NULL,
    wins_count    NUMBER(10) DEFAULT 0 NOT NULL,
    losses_count  NUMBER(10) DEFAULT 0 NOT NULL,
    draws_count   NUMBER(10) DEFAULT 0 NOT NULL,
    joined_at     TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_dtpl PRIMARY KEY (tournament_id, player_id),
    CONSTRAINT fk_dtpl_tournament FOREIGN KEY (tournament_id)
        REFERENCES durak_tournament(tournament_id),
    CONSTRAINT fk_dtpl_player FOREIGN KEY (player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_dtpl_seed CHECK (seed_no IS NULL OR seed_no > 0),
    CONSTRAINT ck_dtpl_status CHECK (
        player_status IN ('REGISTERED', 'ACTIVE', 'ELIMINATED', 'CHAMPION')
    ),
    CONSTRAINT ck_dtpl_values CHECK (
        points >= 0 AND wins_count >= 0 AND losses_count >= 0 AND draws_count >= 0
    )
);

CREATE TABLE durak_tournament_match (
    tournament_match_id NUMBER(19) CONSTRAINT pk_dtm PRIMARY KEY,
    tournament_id       NUMBER(19) NOT NULL,
    tournament_round_no NUMBER(6)  NOT NULL,
    match_no            NUMBER(6)  NOT NULL,
    player1_id          NUMBER(19) NOT NULL,
    player2_id          NUMBER(19),
    game_id             NUMBER(19),
    winner_player_id    NUMBER(19),
    match_status        VARCHAR2(12) DEFAULT 'PLANNED' NOT NULL,
    result_reason       VARCHAR2(40),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    finished_at         TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_dtm_slot UNIQUE (tournament_id, tournament_round_no, match_no),
    CONSTRAINT fk_dtm_tournament FOREIGN KEY (tournament_id)
        REFERENCES durak_tournament(tournament_id),
    CONSTRAINT fk_dtm_player1 FOREIGN KEY (player1_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_dtm_player2 FOREIGN KEY (player2_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT fk_dtm_game FOREIGN KEY (game_id)
        REFERENCES durak_game(game_id),
    CONSTRAINT fk_dtm_winner FOREIGN KEY (winner_player_id)
        REFERENCES durak_player(player_id),
    CONSTRAINT ck_dtm_round CHECK (tournament_round_no > 0 AND match_no > 0),
    CONSTRAINT ck_dtm_status CHECK (
        match_status IN ('PLANNED', 'ACTIVE', 'FINISHED', 'BYE', 'CANCELLED')
    ),
    CONSTRAINT ck_dtm_players CHECK (
        player2_id IS NULL OR player1_id <> player2_id
    )
);

CREATE INDEX ix_dg_status_deadline
    ON durak_game (game_status, action_deadline_at);

CREATE INDEX ix_dg_activity
    ON durak_game (game_status, last_activity_at);

CREATE INDEX ix_dgp_player_status
    ON durak_game_player (player_id, player_status);

CREATE INDEX ix_dgc_zone
    ON durak_game_card (game_id, card_zone, owner_seat_no, deck_pos);

CREATE INDEX ix_dr_status
    ON durak_round (game_id, round_status, round_no);

CREATE INDEX ix_dtp_open
    ON durak_table_pair (game_id, round_no, pair_status);

CREATE INDEX ix_de_game_time
    ON durak_event (game_id, event_no, created_at);

CREATE INDEX ix_der_user_time
    ON durak_error (db_username, created_at);

CREATE INDEX ix_dbd_game
    ON durak_bot_decision (game_id, created_at);

-- До старта турнира SEED_NO не задан у всех участников. В Oracle 26
-- составной UNIQUE-индекс считает одинаковые NULL конфликтом, поэтому
-- индексируем только строки, для которых seed уже распределён.
CREATE UNIQUE INDEX ux_dtpl_seed
    ON durak_tournament_player (
        CASE WHEN seed_no IS NOT NULL THEN tournament_id END,
        CASE WHEN seed_no IS NOT NULL THEN seed_no END
    );

CREATE UNIQUE INDEX ux_dtm_game
    ON durak_tournament_match (game_id);

CREATE INDEX ix_dtm_status
    ON durak_tournament_match (
        tournament_id, match_status, tournament_round_no, match_no
    );

PROMPT Схема проекта DURAK создана
