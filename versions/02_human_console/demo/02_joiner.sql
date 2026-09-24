SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Пример:
-- @demo/02_joiner.sql DURAK_OWNER Анна 1002

DEFINE DURAK_OWNER = '&1'
DEFINE DISPLAY_NAME = '&2'
DEFINE GAME_ID = '&3'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE player_id NUMBER
VARIABLE seat_no NUMBER
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
    durak_api.join_game(
        p_game_id => &&GAME_ID,
        p_seat_no => :seat_no,
        p_message => :message
    );
END;
/

PRINT player_id
PRINT seat_no
PRINT message

SELECT game_id, seat_no, display_name, player_status, hand_count
FROM v_game_status
WHERE game_id = &&GAME_ID
ORDER BY seat_no;

UNDEFINE DURAK_OWNER
UNDEFINE DISPLAY_NAME
UNDEFINE GAME_ID
