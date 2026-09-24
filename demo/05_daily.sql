SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Создание Daily-партии текущим игроком:
-- @demo/05_daily.sql DURAK_OWNER Михаил 2026-09-24

DEFINE DURAK_OWNER = '&1'
DEFINE DISPLAY_NAME = '&2'
DEFINE DAILY_DATE = '&3'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE player_id NUMBER
VARIABLE game_id NUMBER
VARIABLE daily_id NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
    durak_api.register_player(
        p_player_id => :player_id,
        p_message => :message,
        p_display_name => '&&DISPLAY_NAME'
    );
END;
/

BEGIN
    durak_api.create_daily_game(
        p_game_id => :game_id,
        p_daily_id => :daily_id,
        p_message => :message,
        p_daily_date => TO_DATE('&&DAILY_DATE', 'YYYY-MM-DD'),
        p_deck_size => 36,
        p_game_variant => 'PODKIDNOY',
        p_first_move_mode => 'LOWEST_TRUMP'
    );
END;
/

PRINT player_id
PRINT game_id
PRINT daily_id
PRINT message

SELECT daily_id, daily_date, deck_size, game_variant,
       first_move_mode, completed_games, recorded_results
FROM v_daily
WHERE daily_id = :daily_id;

PROMPT Передайте GAME_ID остальным игрокам; они подключаются через demo/02_joiner.sql.

UNDEFINE DURAK_OWNER
UNDEFINE DISPLAY_NAME
UNDEFINE DAILY_DATE
