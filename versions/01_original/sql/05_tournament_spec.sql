PROMPT Создание интерфейса турнирного автомата DURAK_TOURNAMENT_PKG

CREATE OR REPLACE PACKAGE durak_tournament_pkg AUTHID DEFINER AS
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
    );

    PROCEDURE join_tournament (
        p_player_id     IN NUMBER,
        p_tournament_id IN NUMBER
    );

    PROCEDURE add_bot (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER,
        p_bot_level       IN VARCHAR2 DEFAULT 'NORMAL',
        p_bot_player_id   OUT NUMBER
    );

    PROCEDURE start_tournament (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER
    );

    PROCEDURE start_match (
        p_actor_player_id    IN NUMBER,
        p_tournament_match_id IN NUMBER,
        p_game_id            OUT NUMBER
    );

    PROCEDURE cancel_tournament (
        p_actor_player_id IN NUMBER,
        p_tournament_id   IN NUMBER
    );

    -- Вызывается игровым автоматом после окончательного результата партии.
    -- Повторный вызов безопасен: уже обработанный матч не учитывается дважды.
    PROCEDURE record_game_result (
        p_game_id IN NUMBER
    );
END durak_tournament_pkg;
/

SHOW ERRORS PACKAGE durak_tournament_pkg
