PROMPT Создание обработчика таймеров DURAK_MAINTENANCE

CREATE OR REPLACE PACKAGE durak_maintenance AUTHID DEFINER AS
    PROCEDURE process_due_actions (
        p_limit IN NUMBER DEFAULT 100
    );

    PROCEDURE expire_idle_games (
        p_limit IN NUMBER DEFAULT 100
    );

    PROCEDURE run_once;
END durak_maintenance;
/

CREATE OR REPLACE PACKAGE BODY durak_maintenance AS
    TYPE t_game_ids IS TABLE OF durak_game.game_id%TYPE;

    PROCEDURE validate_limit (
        p_limit IN NUMBER
    ) IS
    BEGIN
        IF p_limit IS NULL
           OR p_limit < 1
           OR p_limit > 1000
           OR p_limit <> TRUNC(p_limit) THEN
            RAISE_APPLICATION_ERROR(
                -20820,
                'Лимит обслуживания должен быть целым числом от 1 до 1000.'
            );
        END IF;
    END validate_limit;

    PROCEDURE process_due_actions (
        p_limit IN NUMBER DEFAULT 100
    ) IS
        v_game_ids t_game_ids;
        v_code     NUMBER;
        v_error    VARCHAR2(1000);
    BEGIN
        validate_limit(p_limit);

        SELECT game_id
        BULK COLLECT INTO v_game_ids
        FROM (
            SELECT game_id
            FROM durak_game
            WHERE game_status = 'ACTIVE'
              AND action_deadline_at IS NOT NULL
              AND action_deadline_at <= SYSTIMESTAMP
            ORDER BY action_deadline_at, game_id
        )
        WHERE ROWNUM <= p_limit;

        IF v_game_ids.COUNT > 0 THEN
            FOR i IN 1 .. v_game_ids.COUNT LOOP
                BEGIN
                    SAVEPOINT before_timeout_action;
                    durak_engine.process_timeout(v_game_ids(i));
                    COMMIT;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_code := SQLCODE;
                        v_error := SQLERRM;
                        ROLLBACK TO before_timeout_action;
                        durak_engine.log_rejection(
                            p_game_id => v_game_ids(i),
                            p_player_id => NULL,
                            p_db_username => SYS_CONTEXT('USERENV', 'SESSION_USER'),
                            p_action_type => 'TIMEOUT',
                            p_error_code => v_code,
                            p_error_message => v_error
                        );
                END;
            END LOOP;
        END IF;
    END process_due_actions;

    PROCEDURE expire_idle_games (
        p_limit IN NUMBER DEFAULT 100
    ) IS
        v_game_ids t_game_ids;
        v_code     NUMBER;
        v_error    VARCHAR2(1000);
    BEGIN
        validate_limit(p_limit);

        SELECT game_id
        BULK COLLECT INTO v_game_ids
        FROM (
            SELECT game_id
            FROM durak_game
            WHERE game_status IN ('LOBBY', 'ACTIVE')
              AND last_activity_at <=
                  SYSTIMESTAMP - NUMTODSINTERVAL(idle_timeout_min, 'MINUTE')
            ORDER BY last_activity_at, game_id
        )
        WHERE ROWNUM <= p_limit;

        IF v_game_ids.COUNT > 0 THEN
            FOR i IN 1 .. v_game_ids.COUNT LOOP
                BEGIN
                    SAVEPOINT before_idle_expire;
                    durak_engine.expire_idle_game(v_game_ids(i));
                    COMMIT;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_code := SQLCODE;
                        v_error := SQLERRM;
                        ROLLBACK TO before_idle_expire;
                        durak_engine.log_rejection(
                            p_game_id => v_game_ids(i),
                            p_player_id => NULL,
                            p_db_username => SYS_CONTEXT('USERENV', 'SESSION_USER'),
                            p_action_type => 'IDLE_TIMEOUT',
                            p_error_code => v_code,
                            p_error_message => v_error
                        );
                END;
            END LOOP;
        END IF;
    END expire_idle_games;

    PROCEDURE run_once IS
    BEGIN
        process_due_actions(100);
        expire_idle_games(100);
    END run_once;
END durak_maintenance;
/

SHOW ERRORS PACKAGE durak_maintenance
SHOW ERRORS PACKAGE BODY durak_maintenance
