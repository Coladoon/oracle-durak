SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    v_player1 NUMBER;
    v_player2 NUMBER;
    v_game_id NUMBER;
    v_seat_no NUMBER;
BEGIN
    v_player1 := durak_id_seq.NEXTVAL;
    v_player2 := durak_id_seq.NEXTVAL;

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_player1, 'Concurrency Test Creator', 'BOT', 'EASY'
    );

    INSERT INTO durak_player (
        player_id, display_name, player_type, bot_level
    ) VALUES (
        v_player2, 'Concurrency Test Second', 'BOT', 'EASY'
    );

    durak_engine.create_game(
        p_creator_player_id => v_player1,
        p_seed_text => 'concurrency-test-seed-' || v_player1,
        p_game_id => v_game_id
    );
    durak_engine.join_game(v_player2, v_game_id, v_seat_no);
    durak_engine.start_game(v_player1, v_game_id);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('GAME_ID=' || v_game_id);
    DBMS_OUTPUT.PUT_LINE('PLAYER_ID=' || v_player1);
END;
/
