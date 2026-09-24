PROMPT Удаление объектов проекта DURAK

DECLARE
    PROCEDURE drop_if_exists (
        p_ddl                IN VARCHAR2,
        p_missing_error_code IN NUMBER
    ) IS
    BEGIN
        EXECUTE IMMEDIATE p_ddl;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> p_missing_error_code THEN
                RAISE;
            END IF;
    END drop_if_exists;
BEGIN
    BEGIN
        DBMS_SCHEDULER.DROP_JOB(
            job_name => 'DURAK_MAINTENANCE_JOB',
            force => TRUE
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -27475 THEN
                RAISE;
            END IF;
    END;

    -- Представления удаляются раньше таблиц, от которых они зависят.
    drop_if_exists('DROP VIEW v_game_console', -942);
    drop_if_exists('DROP VIEW v_log_text', -942);
    drop_if_exists('DROP VIEW v_errors', -942);
    drop_if_exists('DROP VIEW v_analytics', -942);
    drop_if_exists('DROP VIEW v_replay', -942);
    drop_if_exists('DROP VIEW v_tournament_standings', -942);
    drop_if_exists('DROP VIEW v_tournament', -942);
    drop_if_exists('DROP VIEW v_daily_results', -942);
    drop_if_exists('DROP VIEW v_daily', -942);
    drop_if_exists('DROP VIEW v_leaderboard', -942);
    drop_if_exists('DROP VIEW v_log', -942);
    drop_if_exists('DROP VIEW v_hand_public', -942);
    drop_if_exists('DROP VIEW v_hand_mine', -942);
    drop_if_exists('DROP VIEW v_table', -942);
    drop_if_exists('DROP VIEW v_game_status', -942);
    drop_if_exists('DROP VIEW v_current_player', -942);

    -- В список включены и пакеты следующих этапов: повторная установка
    -- останется рабочей после расширения проекта.
    drop_if_exists('DROP PACKAGE durak_test', -4043);
    drop_if_exists('DROP PACKAGE durak_maintenance', -4043);
    drop_if_exists('DROP PACKAGE durak_console', -4043);
    drop_if_exists('DROP PACKAGE durak_api', -4043);
    drop_if_exists('DROP PACKAGE durak_tournament_pkg', -4043);
    drop_if_exists('DROP PACKAGE durak_bot', -4043);
    drop_if_exists('DROP PACKAGE durak_engine', -4043);
    drop_if_exists('DROP PACKAGE durak_rules', -4043);
    drop_if_exists('DROP PACKAGE durak_random', -4043);

    -- Таблицы удаляются от дочерних к родительским.
    drop_if_exists(
        'DROP TABLE durak_tournament_match CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_tournament_player CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_tournament CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_bot_decision CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_daily_result CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_error CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_card_move CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_event CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_table_pair CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_round CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_game_card CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_active_session CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_game_player CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_game CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_daily CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_card CASCADE CONSTRAINTS PURGE',
        -942
    );
    drop_if_exists(
        'DROP TABLE durak_player CASCADE CONSTRAINTS PURGE',
        -942
    );

    drop_if_exists('DROP SEQUENCE durak_id_seq', -2289);
END;
/

PROMPT Объекты проекта DURAK удалены
