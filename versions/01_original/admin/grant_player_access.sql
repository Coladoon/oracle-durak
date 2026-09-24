SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

-- Запускать из схемы-владельца проекта:
-- @admin/grant_player_access.sql PLAYER_SCHEMA

DEFINE TARGET_PLAYER = '&1'

DECLARE
    v_username VARCHAR2(128);
BEGIN
    v_username := DBMS_ASSERT.SIMPLE_SQL_NAME(UPPER(TRIM('&&TARGET_PLAYER')));

    EXECUTE IMMEDIATE 'GRANT EXECUTE ON durak_api TO ' || v_username;

    FOR r IN (
        SELECT view_name
        FROM (
            SELECT 'V_CURRENT_PLAYER' AS view_name FROM dual UNION ALL
            SELECT 'V_GAME_STATUS' FROM dual UNION ALL
            SELECT 'V_TABLE' FROM dual UNION ALL
            SELECT 'V_HAND_MINE' FROM dual UNION ALL
            SELECT 'V_HAND_PUBLIC' FROM dual UNION ALL
            SELECT 'V_LOG' FROM dual UNION ALL
            SELECT 'V_REPLAY' FROM dual UNION ALL
            SELECT 'V_ANALYTICS' FROM dual UNION ALL
            SELECT 'V_LEADERBOARD' FROM dual UNION ALL
            SELECT 'V_DAILY' FROM dual UNION ALL
            SELECT 'V_DAILY_RESULTS' FROM dual UNION ALL
            SELECT 'V_TOURNAMENT' FROM dual UNION ALL
            SELECT 'V_TOURNAMENT_STANDINGS' FROM dual UNION ALL
            SELECT 'V_ERRORS' FROM dual
        )
    ) LOOP
        EXECUTE IMMEDIATE
            'GRANT SELECT ON ' || r.view_name || ' TO ' || v_username;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(
        'Доступ к DURAK_API и защищённым представлениям выдан пользователю '
        || v_username || '.'
    );
END;
/

UNDEFINE TARGET_PLAYER
