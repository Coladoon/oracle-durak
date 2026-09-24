SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Создатель запускает после присоединения остальных игроков:
-- @demo/03_start.sql DURAK_OWNER 1002

DEFINE DURAK_OWNER = '&1'
DEFINE GAME_ID = '&2'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE message VARCHAR2(1000)

BEGIN
    durak_api.start_game(
        p_game_id => &&GAME_ID,
        p_message => :message
    );
END;
/

PRINT message

SELECT game_id, phase, trump_card_code, talon_count,
       attacker_name, defender_name, current_actor_name,
       my_allowed_actions
FROM v_game_status
WHERE game_id = &&GAME_ID
  AND seat_no = viewer_seat_no;

SELECT card_code, rank_code, suit_code, is_trump
FROM v_hand_mine
WHERE game_id = &&GAME_ID
ORDER BY is_trump, rank_value, suit_code;

UNDEFINE DURAK_OWNER
UNDEFINE GAME_ID
