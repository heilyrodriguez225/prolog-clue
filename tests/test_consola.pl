/*  Tests de src/consola.pl: la terminal del jugador humano.

    Ninguno usa el teclado ni la pantalla: la entrada sale de un texto y
    la salida se recoge en otro.
*/

:- use_module(library(plunit)).
:- use_module('../src/juego').
:- use_module('../src/consola').

% Ejecuta Goal leyendo de Texto y devuelve lo que escribe en Salida.
ejecutar(Texto, Goal, Salida) :-
    open_string(Texto, Entrada),
    current_input(Anterior),
    setup_call_cleanup(
        set_input(Entrada),
        with_output_to(string(Salida), Goal),
        ( set_input(Anterior), close(Entrada) )).

contiene(Texto, Trozo) :- sub_string(Texto, _, _, _, Trozo), !.

mano_de_la_consola([chef_canela, daga, biblioteca, cocina, piscina]).

:- begin_tests(texto).

test(lista_vacia, [true(T == '')]) :- lista_de_nombres([], T).
test(una_carta, [true(T == 'Daga')]) :- lista_de_nombres([daga], T).
test(dos_cartas, [true(T == 'Daga y Cocina')]) :- lista_de_nombres([daga, cocina], T).
test(tres_cartas, [true(T == 'Chef Canela, Daga y Cocina')]) :- lista_de_nombres([chef_canela, daga, cocina], T).
test(cinco_cartas, [true(T == 'Chef Canela, Trofeo, Cocina, Daga y Piscina')]) :-
    lista_de_nombres([chef_canela, trofeo, cocina, daga, piscina], T).

test(la_mano_sale_en_el_orden_del_mazo) :-
    ejecutar("", mostrar_mano([piscina, cocina, daga, biblioteca, chef_canela]), Salida),
    contiene(Salida, "Chef Canela, Daga, Biblioteca, Cocina y Piscina").

:- end_tests(texto).

:- begin_tests(opciones).

test(un_numero_valido, [true(N == 2)]) :-
    ejecutar("2\n", pedir_opcion(1, 3, N), _).

test(con_espacios_alrededor, [true(N == 3)]) :-
    ejecutar("   3  \n", pedir_opcion(1, 3, N), _).

test(repite_si_no_es_un_numero, [true((N, Hay) == (1, si))]) :-
    ejecutar("hola\n1\n", pedir_opcion(1, 3, N), Salida),
    ( contiene(Salida, "Escribe un número entre 1 y 3") -> Hay = si ; Hay = no ).

test(repite_si_esta_fuera_de_rango, [true(N == 3)]) :-
    ejecutar("0\n4\n-1\n3\n", pedir_opcion(1, 3, N), _).

test(repite_si_no_es_entero, [true(N == 2)]) :-
    ejecutar("1.5\n2\n", pedir_opcion(1, 3, N), _).

test(repite_con_una_linea_vacia, [true(N == 1)]) :-
    ejecutar("\n1\n", pedir_opcion(1, 3, N), _).

test(si_se_acaba_la_entrada_es_un_error, [error(fin_de_la_entrada)]) :-
    ejecutar("", pedir_opcion(1, 3, _), _).

test(si_se_acaba_tras_un_error_tambien, [error(fin_de_la_entrada)]) :-
    ejecutar("mal\n", pedir_opcion(1, 3, _), _).

test(un_menu_devuelve_el_valor_de_la_opcion, [true(V == segunda)]) :-
    ejecutar("2\n", elegir_de_lista("Elige", ['Primera'-primera, 'Segunda'-segunda, 'Tercera'-tercera], V), Salida),
    contiene(Salida, "1) Primera"),
    contiene(Salida, "3) Tercera").

:- end_tests(opciones).

:- begin_tests(preguntar_la_accion).

vista_de_prueba(Historial, vista(Mano, [], Historial)) :- mano_de_la_consola(Mano).

test(sugerir_con_las_primeras_opciones, [true(A == sugerir(chef_canela, trofeo, biblioteca))]) :-
    vista_de_prueba([], V),
    ejecutar("1\n1\n1\n1\n", preguntar_accion(1, V, A), _).

test(sugerir_con_otras_cartas, [true(A == sugerir(senorita_perla, tijeras, jardin))]) :-
    vista_de_prueba([], V),
    ejecutar("1\n6\n6\n9\n", preguntar_accion(1, V, A), _).

test(acusar_pide_confirmacion_y_acusa, [true(A == acusar(senora_coral, cuerda, gimnasio))]) :-
    vista_de_prueba([], V),
    ejecutar("2\n3\n3\n8\n1\n", preguntar_accion(1, V, A), Salida),
    contiene(Salida, "Si te equivocas quedas eliminado").

test(si_no_confirma_vuelve_a_empezar_el_turno, [true(A == sugerir(chef_canela, trofeo, biblioteca))]) :-
    vista_de_prueba([], V),
    ejecutar("2\n1\n1\n1\n2\n1\n1\n1\n1\n", preguntar_accion(1, V, A), _).

test(puede_ver_el_historial_y_seguir, [true(A == sugerir(chef_canela, trofeo, biblioteca))]) :-
    vista_de_prueba([sugerencia(2, [entrenador_cobalto, veneno, estudio], [no_pudo(3), refuto(4)])], V),
    ejecutar("3\n1\n1\n1\n1\n", preguntar_accion(1, V, A), Salida),
    contiene(Salida, "-- Historial --"),
    contiene(Salida, "El jugador 2 sugiere: Entrenador Cobalto, Veneno y Estudio"),
    contiene(Salida, "El jugador 4 refutó").

test(muestra_la_mano_al_empezar_el_turno) :-
    vista_de_prueba([], V),
    ejecutar("1\n1\n1\n1\n", preguntar_accion(1, V, _), Salida),
    contiene(Salida, "== Tu turno =="),
    contiene(Salida, "Tus cartas: Chef Canela, Daga, Biblioteca, Cocina y Piscina").

test(avisa_de_las_cartas_que_ya_tienes) :-
    vista_de_prueba([], V),
    ejecutar("1\n1\n1\n1\n", preguntar_accion(1, V, _), Salida),
    contiene(Salida, "Chef Canela (la tienes tú)"),
    contiene(Salida, "Daga (la tienes tú)"),
    \+ contiene(Salida, "Trofeo (la tienes tú)").

test(repite_la_pregunta_si_escribe_algo_raro, [true(A == sugerir(chef_canela, trofeo, biblioteca))]) :-
    vista_de_prueba([], V),
    ejecutar("sugerir\n9\n1\n1\n1\n1\n", preguntar_accion(1, V, A), _).

test(la_accion_es_siempre_valida) :-
    vista_de_prueba([], V),
    forall(( between(1, 6, S), between(1, 6, A), member(L, [1, 9]) ),
           ( format(string(Entrada), "1\n~w\n~w\n~w\n", [S, A, L]),
             ejecutar(Entrada, preguntar_accion(1, V, Accion), _),
             Accion = sugerir(Sosp, Arma, Lugar),
             carta(sospechoso, Sosp), carta(arma, Arma), carta(lugar, Lugar) )).

test(la_pantalla_no_muestra_cartas_que_no_conoce) :-
    % Solo sale lo que viene en la vista: aquí, la mano de prueba y el historial.
    vista_de_prueba([], V),
    ejecutar("3\n1\n1\n1\n1\n", preguntar_accion(1, V, _), Salida),
    contiene(Salida, "(todavía no ha pasado nada)").

:- end_tests(preguntar_la_accion).

:- begin_tests(refutar).

test(con_una_sola_carta_no_hay_nada_que_elegir, [true(C == trofeo)]) :-
    % La entrada está vacía: si pidiera algo, fallaría con fin_de_la_entrada.
    ejecutar("", preguntar_carta(sugerencia(2, [chef_canela, trofeo, cocina]), [trofeo], C), Salida),
    contiene(Salida, "solo puedes enseñar: Trofeo").

test(con_varias_elige_una, [true(C == cocina)]) :-
    ejecutar("2\n", preguntar_carta(sugerencia(2, [chef_canela, trofeo, cocina]), [chef_canela, cocina], C), Salida),
    contiene(Salida, "El jugador 2 sugiere: Chef Canela, Trofeo y Cocina"),
    contiene(Salida, "1) Chef Canela"),
    contiene(Salida, "2) Cocina").

test(solo_se_puede_enseniar_una_de_las_candidatas, [forall(member(Entrada, ["1\n", "2\n", "3\n"]))]) :-
    Candidatas = [chef_canela, trofeo, cocina],
    ejecutar(Entrada, preguntar_carta(sugerencia(2, Candidatas), Candidatas, C), _),
    memberchk(C, Candidatas).

:- end_tests(refutar).

:- begin_tests(eventos_en_pantalla).

salida_de(Yo, Evento, Salida) :- ejecutar("", mostrar_evento(Yo, Evento), Salida).

test(sugerencia_de_otro_con_refutacion) :-
    salida_de(1, sugerencia(2, [chef_canela, trofeo, cocina], [no_pudo(3), refuto(4)]), S),
    contiene(S, "El jugador 2 sugiere: Chef Canela, Trofeo y Cocina."),
    contiene(S, "El jugador 3 no pudo refutar."),
    contiene(S, "El jugador 4 refutó."),
    \+ contiene(S, "Nadie pudo refutar").

test(sugerencia_propia) :-
    salida_de(1, sugerencia(1, [chef_canela, trofeo, cocina], [refuto(2)]), S),
    contiene(S, "Sugieres: Chef Canela, Trofeo y Cocina.").

test(nadie_pudo_refutar) :-
    salida_de(1, sugerencia(2, [chef_canela, trofeo, cocina], [no_pudo(3), no_pudo(4)]), S),
    contiene(S, "Nadie pudo refutar").

test(cuando_el_jugador_no_tenia_ninguna_carta) :-
    salida_de(1, sugerencia(2, [chef_canela, trofeo, cocina], [no_pudo(1), refuto(3)]), S),
    contiene(S, "No tenías ninguna de esas cartas").

test(cuando_refuta_el_propio_jugador) :-
    salida_de(1, sugerencia(2, [chef_canela, trofeo, cocina], [refuto(1)]), S),
    contiene(S, "Refutaste tú").

test(la_sugerencia_publica_no_dice_que_carta_se_enseño) :-
    % Quien refuta es público; la carta, no.
    salida_de(1, sugerencia(2, [chef_canela, trofeo, cocina], [refuto(3)]), S),
    \+ contiene(S, "te enseña").

test(la_carta_que_te_ensenan) :-
    salida_de(1, carta_vista(3, veneno), S),
    contiene(S, "El jugador 3 te enseña: Veneno.").

test(acusacion_ajena_que_falla) :-
    salida_de(1, acusacion(2, [chef_canela, trofeo, cocina], falla), S),
    contiene(S, "El jugador 2 acusa a: Chef Canela, Trofeo y Cocina."),
    contiene(S, "queda eliminado").

test(acusacion_ajena_que_acierta) :-
    salida_de(1, acusacion(2, [chef_canela, trofeo, cocina], acierta), S),
    contiene(S, "¡Ha acertado!").

test(acusacion_propia_que_falla) :-
    salida_de(1, acusacion(1, [chef_canela, trofeo, cocina], falla), S),
    contiene(S, "Acusas a:"),
    contiene(S, "sigues refutando").

test(acusacion_propia_que_acierta) :-
    salida_de(1, acusacion(1, [chef_canela, trofeo, cocina], acierta), S),
    contiene(S, "¡Has acertado!").

test(un_evento_desconocido_no_rompe_la_pantalla) :-
    salida_de(1, algo_raro(1), S),
    contiene(S, "algo_raro").

test(historial_vacio) :-
    ejecutar("", mostrar_historial(1, []), S),
    contiene(S, "(todavía no ha pasado nada)").

test(historial_con_eventos_en_orden) :-
    ejecutar("", mostrar_historial(1, [sugerencia(2, [chef_canela, trofeo, cocina], [refuto(3)]),
                                       acusacion(3, [daga, veneno, estudio], falla)]), S),
    once(sub_string(S, A, _, _, "El jugador 2 sugiere")),
    once(sub_string(S, B, _, _, "El jugador 3 acusa")),
    A < B.

:- end_tests(eventos_en_pantalla).

:- begin_tests(fin_en_pantalla).

partida_final(Eliminados, partida(sobre(senora_coral, cuerda, gimnasio),
                                  [1-[], 2-[], 3-[]], 1, Eliminados, [])).

test(gana_otro_acertando) :-
    partida_final([], P),
    ejecutar("", mostrar_fin(1, fin(2, acierta, P, [])), S),
    contiene(S, "== Fin de la partida =="),
    contiene(S, "Gana el jugador 2: acusó correctamente."),
    contiene(S, "El sobre era: Señora Coral, Cuerda y Gimnasio.").

test(ganas_tu) :-
    partida_final([], P),
    ejecutar("", mostrar_fin(1, fin(1, acierta, P, [])), S),
    contiene(S, "Gana tú").

test(gana_el_ultimo_que_queda) :-
    partida_final([2, 3], P),
    ejecutar("", mostrar_fin(1, fin(1, ultimo, P, [])), S),
    contiene(S, "único jugador que queda sin eliminar"),
    contiene(S, "Eliminados, por orden: [2,3]").

test(si_no_hay_eliminados_no_los_menciona) :-
    partida_final([], P),
    ejecutar("", mostrar_fin(1, fin(2, acierta, P, [])), S),
    \+ contiene(S, "Eliminados").

:- end_tests(fin_en_pantalla).
