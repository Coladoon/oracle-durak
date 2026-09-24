SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Шаблоны команд. Подставьте владельца схемы, GAME_ID и код карты:
-- @demo/04_actions.sql DURAK_OWNER 1002

DEFINE DURAK_OWNER = '&1'
DEFINE GAME_ID = '&2'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE message VARCHAR2(1000)

PROMPT Сначала смотрите состояние, стол и свою руку:

SELECT phase, current_actor_name, my_allowed_actions,
       trump_card_code, talon_count
FROM v_game_status
WHERE game_id = &&GAME_ID
  AND seat_no = viewer_seat_no;

SELECT pair_no, attack_card_code, defense_card_code,
       pair_status, allowed_actions
FROM v_table
WHERE game_id = &&GAME_ID
ORDER BY pair_no;

SELECT card_code, rank_value, suit_code, is_trump
FROM v_hand_mine
WHERE game_id = &&GAME_ID
ORDER BY is_trump, rank_value, suit_code;

PROMPT Примеры действий (снимите комментарий только с нужного блока):

-- BEGIN
--     durak_api.attack(&&GAME_ID, '6C', :message);
-- END;
-- /

-- BEGIN
--     durak_api.defend(&&GAME_ID, '7C', :message, 1);
-- END;
-- /

-- BEGIN
--     durak_api.throw_in(&&GAME_ID, '6D', :message);
-- END;
-- /

-- BEGIN
--     durak_api.pass_throw(&&GAME_ID, :message);
-- END;
-- /

-- BEGIN
--     durak_api.take_cards(&&GAME_ID, :message);
-- END;
-- /

-- BEGIN
--     durak_api.transfer_attack(&&GAME_ID, '6H', :message);
-- END;
-- /

-- PRINT message

UNDEFINE DURAK_OWNER
UNDEFINE GAME_ID
