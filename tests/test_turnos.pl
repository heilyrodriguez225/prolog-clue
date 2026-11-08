/*  Tests de src/turnos.pl: el bucle de la partida.  */

:- use_module(library(plunit)).
:- use_module('../src/juego').
:- use_module('../src/jugador').
:- use_module('../src/turnos').

:- begin_tests(estado).

test(iniciar_partida_crea_un_jugador_por_tipo) :-
    iniciar_partida([humano, media, facil], Partida, Jugadores),
    Partida = partida(_, Manos, 1, [], []),
    length(Manos, 3),
    Jugadores = [jugador(1, humano, _), jugador(2, media, _), jugador(3, facil, _)].

test(iniciar_partida_de_3_a_5_jugadores, [forall(member(N, [3, 4, 5]))]) :-
    length(Tipos, N), maplist(=(media), Tipos),
    iniciar_partida(Tipos, partida(_, Manos, _, _, _), Jugadores),
    length(Manos, N),
    length(Jugadores, N).

test(iniciar_partida_con_2_jugadores_da_error,
     [error(type_error(between(3, 5), 2))]) :-
    iniciar_partida([humano, media], _, _).

test(iniciar_partida_con_6_jugadores_da_error,
     [error(type_error(between(3, 5), 6))]) :-
    iniciar_partida([humano, media, media, media, media, media], _, _).

test(un_tipo_desconocido_da_error,
     [error(type_error(oneof(_), robot))]) :-
    iniciar_partida([humano, robot, media], _, _).

test(las_ias_empiezan_conociendo_su_mano) :-
    iniciar_partida([humano, facil, facil], partida(_, Manos, _, _, _), Js),
    memberchk(2-Mano2, Manos),
    jugador_con_id(2, Js, jugador(2, facil, vistas(Vistas))),
    msort(Mano2, A), msort(Vistas, B),
    A == B.

:- end_tests(estado).

:- begin_tests(lista_de_jugadores).

jugadores_de_prueba([jugador(1, humano, []),
                     jugador(2, facil, vistas([daga])),
                     jugador(3, media, k3)]).

test(jugador_con_id, [true(J == jugador(2, facil, vistas([daga])))]) :-
    jugadores_de_prueba(Js),
    jugador_con_id(2, Js, J).

test(jugador_con_id_que_no_existe, [error(existence_error(jugador, 7))]) :-
    jugadores_de_prueba(Js),
    jugador_con_id(7, Js, _).

test(reemplazar_conserva_el_orden_y_a_los_demas) :-
    jugadores_de_prueba(Js),
    reemplazar_jugador(Js, jugador(2, facil, vistas([daga, trofeo])), Js1),
    Js1 == [jugador(1, humano, []),
            jugador(2, facil, vistas([daga, trofeo])),
            jugador(3, media, k3)].

test(reemplazar_el_primero_y_el_ultimo, [forall(member(Id, [1, 3]))]) :-
    jugadores_de_prueba(Js),
    jugador_con_id(Id, Js, jugador(Id, T, _)),
    reemplazar_jugador(Js, jugador(Id, T, nueva), Js1),
    jugador_con_id(Id, Js1, jugador(Id, T, nueva)),
    length(Js1, 3).

test(reemplazar_uno_que_no_existe, [error(existence_error(jugador, 9))]) :-
    jugadores_de_prueba(Js),
    reemplazar_jugador(Js, jugador(9, facil, vistas([])), _).

test(reemplazar_es_determinista) :-
    % Sin la opción nondet, plunit avisa si queda algún punto de elección.
    jugadores_de_prueba(Js),
    reemplazar_jugador(Js, jugador(1, humano, []), _),
    reemplazar_jugador(Js, jugador(3, media, otra), _).

:- end_tests(lista_de_jugadores).

% Tipos de jugador para una partida de N. Las partidas masivas usan los tipos
% baratos; la IA media, que deduce con restricciones y es la más lenta, se prueba
% en menos partidas (ver más abajo).
tipos_variados(N, Tipos) :-
    tipos_de(N, [azar, facil, facil, azar], Tipos).

tipos_con_media(N, Tipos) :-
    tipos_de(N, [media, facil, azar, azar], Tipos).

tipos_de(N, Todos, Tipos) :-
    numlist(1, N, Numeros),
    maplist(tipo_numero(Todos), Numeros, Tipos).

tipo_numero(Todos, Numero, Tipo) :-
    length(Todos, L),
    Posicion is (Numero - 1) mod L,
    nth0(Posicion, Todos, Tipo).

% La partida de los tests: 4 jugadores, con el turno que se indique.
partida_en_turno(Turno, Eliminados,
                 partida(sobre(senora_coral, cuerda, gimnasio),
                         [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                           2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                           3-[doctora_violeta, veneno, estudio, bodega],
                           4-[jardinero_verde, senorita_perla, revolver, tijeras]
                         ],
                         Turno, Eliminados, [])).

:- begin_tests(accion_valida).

test(sugerir_y_acusar_con_cartas_de_su_tipo) :-
    accion_valida(sugerir(chef_canela, trofeo, cocina)),
    accion_valida(acusar(senora_coral, cuerda, gimnasio)).

test(una_carta_de_otro_tipo_no_vale, [fail]) :-
    accion_valida(sugerir(trofeo, chef_canela, cocina)).

test(el_orden_importa_sospechoso_arma_lugar, [fail]) :-
    accion_valida(sugerir(chef_canela, cocina, trofeo)).

test(una_carta_que_no_existe_no_vale, [fail]) :-
    accion_valida(sugerir(chef_canela, trofeo, el_sotano)).

test(otra_accion_no_vale, [fail]) :-
    accion_valida(pasar(chef_canela, trofeo, cocina)).

test(una_accion_sin_instanciar_no_vale, [fail]) :-
    accion_valida(_).

test(una_accion_incompleta_no_vale, [fail]) :-
    accion_valida(sugerir(chef_canela, trofeo)).

:- end_tests(accion_valida).

:- begin_tests(un_turno).

% La IA difícil piensa con muestras (medio segundo por decisión): menos repeticiones.
veces(dificil, 2) :- !.
veces(_, 15).

test(da_una_accion_valida_para_cada_tipo, [forall(member(Tipo, [facil, media, dificil, azar]))]) :-
    partida_en_turno(1, [], P),
    jugadores_iniciales(P, [Tipo, facil, facil, facil], Js),
    veces(Tipo, Veces),
    forall(between(1, Veces, _),
           ( accion_del_turno(P, Js, Accion, _),
             accion_valida(Accion) )).

test(juega_el_jugador_al_que_le_toca, [forall(member(Turno, [1, 2, 3, 4]))]) :-
    partida_en_turno(Turno, [], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    accion_del_turno(P, Js, _, Js1),
    length(Js1, 4),
    forall(member(Id, [1, 2, 3, 4]), jugador_con_id(Id, Js1, jugador(Id, facil, _))).

test(los_demas_jugadores_quedan_igual) :-
    partida_en_turno(2, [], P),
    jugadores_iniciales(P, [facil, media, facil, media], Js),
    accion_del_turno(P, Js, _, Js1),
    jugador_con_id(1, Js, J1), jugador_con_id(1, Js1, J1b), J1 == J1b,
    jugador_con_id(3, Js, J3), jugador_con_id(3, Js1, J3b), J3 == J3b,
    jugador_con_id(4, Js, J4), jugador_con_id(4, Js1, J4b), J4 == J4b.

test(un_jugador_eliminado_no_juega, [error(domain_error(jugador_en_juego, 3))]) :-
    partida_en_turno(3, [3], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    accion_del_turno(P, Js, _, _).

test(un_turno_de_un_jugador_que_no_existe, [error(existence_error(jugador, 6))]) :-
    partida_en_turno(6, [], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    accion_del_turno(P, Js, _, _).

:- end_tests(un_turno).

:- begin_tests(orden_de_consulta).

test(empieza_por_el_siguiente, [true(O == [2, 3, 4])]) :-
    orden_de_consulta(1, 4, O).

test(da_la_vuelta, [true(O == [4, 1, 2])]) :-
    orden_de_consulta(3, 4, O).

test(el_ultimo_pregunta_al_primero, [true(O == [1, 2, 3])]) :-
    orden_de_consulta(4, 4, O).

test(con_3_jugadores, [true(O == [3, 1])]) :-
    orden_de_consulta(2, 3, O).

test(con_5_jugadores, [true(O == [4, 5, 1, 2])]) :-
    orden_de_consulta(3, 5, O).

test(nunca_incluye_al_que_sugiere_y_son_todos_los_demas,
     [forall((member(N, [3, 4, 5]), between(1, N, Quien)))]) :-
    orden_de_consulta(Quien, N, Orden),
    \+ memberchk(Quien, Orden),
    length(Orden, L), L =:= N - 1,
    sort(Orden, Unicos), length(Unicos, L).

:- end_tests(orden_de_consulta).

:- begin_tests(sugerencia).

% Resuelve una sugerencia en la partida de pruebas, con jugadores fáciles.
resolver(Quien, Eliminados, Cartas, Respuestas, Refutacion) :-
    partida_en_turno(Quien, Eliminados, P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    resolver_sugerencia(P, Js, Quien, Cartas, Respuestas, Refutacion, Js1),
    length(Js1, 4).

test(nadie_puede_refutar,
     [true((R, M) == ([no_pudo(2), no_pudo(3), no_pudo(4)], ninguna))]) :-
    resolver(1, [], [senora_coral, cuerda, gimnasio], R, M).

test(refuta_el_primero_y_no_se_pregunta_a_los_demas,
     [true((R, M) == ([refuto(2)], mostrada(2, entrenador_cobalto)))]) :-
    % Los jugadores 3 y 4 también tienen alguna carta, pero no se les pregunta.
    resolver(1, [], [entrenador_cobalto, veneno, revolver], R, M).

test(se_salta_a_los_que_no_tienen_ninguna,
     [true((R, M) == ([no_pudo(2), refuto(3)], mostrada(3, veneno)))]) :-
    resolver(1, [], [senora_coral, veneno, gimnasio], R, M).

test(el_orden_es_circular,
     [true((R, M) == ([no_pudo(4), refuto(1)], mostrada(1, chef_canela)))]) :-
    resolver(3, [], [chef_canela, cuerda, gimnasio], R, M).

test(el_que_sugiere_no_se_refuta_a_si_mismo,
     [true((R, M) == ([no_pudo(2), no_pudo(3), no_pudo(4)], ninguna))]) :-
    % Las tres cartas son del jugador 1, que es quien sugiere.
    resolver(1, [], [chef_canela, daga, biblioteca], R, M).

test(los_eliminados_siguen_refutando,
     [true((R, M) == ([refuto(2)], mostrada(2, entrenador_cobalto)))]) :-
    resolver(1, [2], [entrenador_cobalto, veneno, revolver], R, M).

test(con_varias_candidatas_ensenia_una_de_ellas) :-
    % El jugador 3 tiene las tres cartas de la sugerencia.
    forall(between(1, 40, _),
           ( resolver(1, [], [doctora_violeta, veneno, estudio], R, M),
             R == [no_pudo(2), refuto(3)],
             M = mostrada(3, Carta),
             memberchk(Carta, [doctora_violeta, veneno, estudio]) )).

test(la_carta_ensenada_es_siempre_de_quien_refuta) :-
    partida_en_turno(1, [], P),
    P = partida(_, Manos, _, _, _),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    forall(between(1, 60, _),
           ( findall(C, carta(sospechoso, C), Ss), random_member(S, Ss),
             findall(C, carta(arma, C), As), random_member(A, As),
             findall(C, carta(lugar, C), Ls), random_member(L, Ls),
             resolver_sugerencia(P, Js, 1, [S, A, L], _, Refutacion, _),
             (   Refutacion = mostrada(Id, Carta)
             ->  memberchk(Id-Mano, Manos), memberchk(Carta, Mano),
                 memberchk(Carta, [S, A, L])
             ;   true ) )).

test(las_respuestas_terminan_en_refuto_o_son_todas_no_pudo) :-
    partida_en_turno(1, [], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    forall(between(1, 60, _),
           ( findall(C, carta(sospechoso, C), Ss), random_member(S, Ss),
             findall(C, carta(arma, C), As), random_member(A, As),
             findall(C, carta(lugar, C), Ls), random_member(L, Ls),
             resolver_sugerencia(P, Js, 1, [S, A, L], R, M, _),
             (   M == ninguna
             ->  length(R, 3), \+ memberchk(refuto(_), R)
             ;   last(R, refuto(_)),
                 findall(X, (member(X, R), X = refuto(_)), [_]) ) )).

:- end_tests(sugerencia).

:- begin_tests(historial).

test(el_evento_va_al_final) :-
    partida_en_turno(1, [], P),
    Primero = sugerencia(1, [chef_canela, trofeo, cocina], [no_pudo(2)]),
    Segundo = acusacion(2, [chef_canela, trofeo, cocina], falla),
    agregar_al_historial(P, Primero, P1),
    agregar_al_historial(P1, Segundo, P2),
    P2 = partida(_, _, _, _, Historial),
    Historial == [Primero, Segundo].

test(solo_entran_eventos_publicos) :-
    partida_en_turno(1, [], P),
    agregar_al_historial(P, sugerencia(1, [chef_canela, trofeo, cocina], [no_pudo(2)]), P1),
    P1 = partida(_, _, _, _, [sugerencia(1, _, _)]).

test(un_evento_privado_no_entra, [error(domain_error(evento_publico, carta_vista(2, trofeo)))]) :-
    partida_en_turno(1, [], P),
    agregar_al_historial(P, carta_vista(2, trofeo), _).

test(el_resto_de_la_partida_no_cambia) :-
    partida_en_turno(3, [4], P),
    agregar_al_historial(P, acusacion(1, [chef_canela, trofeo, cocina], falla),
                         partida(Sobre, Manos, Turno, Eliminados, [_])),
    P = partida(Sobre, Manos, Turno, Eliminados, []).

:- end_tests(historial).

:- begin_tests(jugar_sugerencia).

% Cuatro IAs fáciles: son las que recuerdan las cartas que les enseñan.
con_facil(Turno, P, Js) :-
    partida_en_turno(Turno, [], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js).

vistas_de(Id, Js, Vistas) :-
    jugador_con_id(Id, Js, jugador(Id, facil, vistas(Vistas))).

test(la_sugerencia_queda_en_el_historial,
     [true(H == [sugerencia(1, [entrenador_cobalto, veneno, revolver], [refuto(2)])])]) :-
    con_facil(1, P, Js),
    jugar_sugerencia(P, Js, 1, [entrenador_cobalto, veneno, revolver], P1, _),
    P1 = partida(_, _, _, _, H).

test(si_nadie_refuta_el_historial_lo_dice,
     [true(H == [sugerencia(1, [senora_coral, cuerda, gimnasio],
                            [no_pudo(2), no_pudo(3), no_pudo(4)])])]) :-
    con_facil(1, P, Js),
    jugar_sugerencia(P, Js, 1, [senora_coral, cuerda, gimnasio], P1, _),
    P1 = partida(_, _, _, _, H).

test(el_historial_no_guarda_la_carta_enseniada) :-
    con_facil(1, P, Js),
    jugar_sugerencia(P, Js, 1, [entrenador_cobalto, veneno, revolver], P1, _),
    P1 = partida(_, _, _, _, H),
    \+ sub_term(carta_vista(_, _), H),
    \+ sub_term(mostrada(_, _), H).

test(la_carta_enseniada_solo_la_conoce_quien_sugirio) :-
    % El jugador 3 refuta con el veneno. Nadie más que el jugador 1 la ve.
    con_facil(1, P, Js),
    jugar_sugerencia(P, Js, 1, [senora_coral, veneno, gimnasio], _, Js1),
    vistas_de(1, Js1, V1), vistas_de(2, Js1, V2), vistas_de(4, Js1, V4),
    memberchk(veneno, V1),
    \+ memberchk(veneno, V2),
    \+ memberchk(veneno, V4).

test(si_nadie_refuta_no_se_ve_ninguna_carta) :-
    con_facil(1, P, Js),
    vistas_de(1, Js, Antes),
    jugar_sugerencia(P, Js, 1, [senora_coral, cuerda, gimnasio], _, Js1),
    vistas_de(1, Js1, Despues),
    Antes == Despues.

test(el_turno_y_el_resto_de_la_partida_no_cambian) :-
    con_facil(2, P, Js),
    jugar_sugerencia(P, Js, 2, [chef_canela, veneno, gimnasio], P1, _),
    P = partida(Sobre, Manos, Turno, Eliminados, _),
    P1 = partida(Sobre, Manos, Turno, Eliminados, _).

test(dos_sugerencias_quedan_en_orden_cronologico) :-
    con_facil(1, P, Js),
    jugar_sugerencia(P, Js, 1, [entrenador_cobalto, veneno, revolver], P1, Js1),
    jugar_sugerencia(P1, Js1, 2, [chef_canela, veneno, gimnasio], P2, _),
    P2 = partida(_, _, _, _, [sugerencia(1, _, _), sugerencia(2, _, _)]).

test(la_lista_de_jugadores_conserva_su_forma, [forall(member(Quien, [1, 2, 3, 4]))]) :-
    con_facil(Quien, P, Js),
    jugar_sugerencia(P, Js, Quien, [chef_canela, trofeo, cocina], _, Js1),
    length(Js1, 4),
    forall(member(Id, [1, 2, 3, 4]), jugador_con_id(Id, Js1, jugador(Id, facil, _))).

:- end_tests(jugar_sugerencia).

:- begin_tests(acusacion).

% El sobre de la partida de pruebas es senora_coral, cuerda, gimnasio.
acusa(Quien, Eliminados, Cartas, Resultado, P1, Js1) :-
    partida_en_turno(Quien, Eliminados, P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    jugar_acusacion(P, Js, Quien, Cartas, Resultado, P1, Js1).

test(acierta_si_son_las_cartas_del_sobre) :-
    acusa(2, [], [senora_coral, cuerda, gimnasio], acierta, P1, _),
    P1 = partida(_, _, _, [], [acusacion(2, [senora_coral, cuerda, gimnasio], acierta)]).

test(acertar_no_elimina_a_nadie) :-
    acusa(2, [], [senora_coral, cuerda, gimnasio], _, partida(_, _, _, Eliminados, _), _),
    Eliminados == [].

test(falla_con_una_sola_carta_mal,
     [forall(member(Mala, [[chef_canela, cuerda, gimnasio],
                           [senora_coral, trofeo, gimnasio],
                           [senora_coral, cuerda, cocina]]))]) :-
    acusa(2, [], Mala, falla, _, _).

test(falla_con_las_tres_mal) :-
    acusa(2, [], [chef_canela, trofeo, cocina], falla, _, _).

test(quien_falla_queda_eliminado) :-
    acusa(2, [], [chef_canela, trofeo, cocina], falla, partida(_, _, _, Eliminados, _), _),
    Eliminados == [2].

test(los_eliminados_se_guardan_en_orden) :-
    acusa(3, [2], [chef_canela, trofeo, cocina], falla, partida(_, _, _, Eliminados, _), _),
    Eliminados == [2, 3].

test(el_historial_recoge_la_acusacion) :-
    acusa(2, [], [chef_canela, trofeo, cocina], falla, partida(_, _, _, _, H), _),
    H == [acusacion(2, [chef_canela, trofeo, cocina], falla)].

test(el_historial_no_revela_que_parte_estaba_mal) :-
    % La acusación fallida no filtra ninguna carta del sobre.
    acusa(2, [], [chef_canela, trofeo, cocina], falla, partida(_, _, _, _, H), _),
    \+ sub_term(senora_coral, H),
    \+ sub_term(cuerda, H),
    \+ sub_term(gimnasio, H).

test(el_eliminado_conserva_su_mano_y_su_sitio_en_la_lista) :-
    partida_en_turno(2, [], P0),
    jugadores_iniciales(P0, [facil, facil, facil, facil], Js),
    jugar_acusacion(P0, Js, 2, [chef_canela, trofeo, cocina], falla, P1, Js1),
    P0 = partida(_, Manos, _, _, _),
    P1 = partida(_, Manos1, _, _, _),
    Manos == Manos1,
    length(Js1, 4),
    jugador_con_id(2, Js1, jugador(2, facil, _)).

test(el_resto_de_la_partida_no_cambia) :-
    partida_en_turno(2, [], P0),
    jugadores_iniciales(P0, [facil, facil, facil, facil], Js),
    jugar_acusacion(P0, Js, 2, [chef_canela, trofeo, cocina], falla, P1, _),
    P0 = partida(Sobre, Manos, Turno, _, _),
    P1 = partida(Sobre, Manos, Turno, _, _).

test(un_eliminado_sigue_refutando_despues_de_acusar) :-
    % Tras fallar, el jugador 2 sigue en la partida y se le sigue preguntando.
    partida_en_turno(2, [], P0),
    jugadores_iniciales(P0, [facil, facil, facil, facil], Js),
    jugar_acusacion(P0, Js, 2, [chef_canela, trofeo, cocina], falla, P1, Js1),
    resolver_sugerencia(P1, Js1, 1, [entrenador_cobalto, veneno, revolver], R, M, _),
    R == [refuto(2)],
    M = mostrada(2, entrenador_cobalto).

:- end_tests(acusacion).

:- begin_tests(siguiente_turno).

siguiente(Turno, Eliminados, Siguiente) :-
    partida_en_turno(Turno, Eliminados, P),
    siguiente_turno(P, partida(_, _, Siguiente, _, _)).

test(pasa_al_siguiente, [true(S == 2)]) :- siguiente(1, [], S).
test(el_ultimo_pasa_al_primero, [true(S == 1)]) :- siguiente(4, [], S).
test(salta_a_un_eliminado, [true(S == 3)]) :- siguiente(1, [2], S).
test(salta_a_varios_eliminados, [true(S == 4)]) :- siguiente(1, [2, 3], S).
test(salta_dando_la_vuelta, [true(S == 2)]) :- siguiente(3, [4, 1], S).
test(el_que_acaba_de_jugar_puede_estar_eliminado, [true(S == 3)]) :-
    % Acaba de acusar mal el jugador 2 y por eso está eliminado.
    siguiente(2, [2], S).
test(si_solo_queda_uno_el_turno_no_se_mueve, [true(S == 1)]) :- siguiente(1, [2, 3, 4], S).

test(solo_cambia_el_turno) :-
    partida_en_turno(1, [3], P),
    siguiente_turno(P, P1),
    P = partida(Sobre, Manos, _, Eliminados, Historial),
    P1 = partida(Sobre, Manos, _, Eliminados, Historial).

test(jugadores_en_juego, [true(Ids == [1, 3])]) :-
    partida_en_turno(1, [2, 4], P),
    jugadores_en_juego(P, Ids).

test(sin_eliminados_estan_todos, [true(Ids == [1, 2, 3, 4])]) :-
    partida_en_turno(1, [], P),
    jugadores_en_juego(P, Ids).

:- end_tests(siguiente_turno).

:- begin_tests(jugar).

jugar_con(Tipos, Resultado) :-
    iniciar_partida(Tipos, P, Js),
    jugar(P, Js, Resultado).

test(si_solo_queda_uno_sin_eliminar_gana_sin_jugar, [true(Resultado == fin(1, ultimo, P, Js))]) :-
    partida_en_turno(1, [2, 3, 4], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    jugar(P, Js, Resultado).

test(el_ultimo_puede_ser_cualquiera, [forall(member(Ultimo, [1, 2, 3, 4]))]) :-
    findall(Id, (member(Id, [1, 2, 3, 4]), Id \== Ultimo), Eliminados),
    partida_en_turno(Ultimo, Eliminados, P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    jugar(P, Js, fin(Ganador, Motivo, _, _)),
    Ganador == Ultimo,
    Motivo == ultimo.

test(una_partida_termina_con_un_ganador, [forall((member(N, [3, 4, 5]), member(Tipo, [azar, facil])))]) :-
    length(Tipos, N), maplist(=(Tipo), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(Ganador, Motivo, _, Js)),
             integer(Ganador), Ganador >= 1, Ganador =< N,
             memberchk(Motivo, [acierta, ultimo]),
             length(Js, N) )).

test(con_ias_faciles_gana_quien_acierta_y_es_lo_ultimo_del_historial, [forall(member(N, [3, 4, 5]))]) :-
    % Una IA fácil solo acusa cuando está segura, así que estas partidas
    % siempre terminan acertando.
    length(Tipos, N), maplist(=(facil), Tipos),
    forall(between(1, 20, _),
           ( jugar_con(Tipos, fin(Ganador, Motivo, partida(sobre(S, A, L), _, _, Eliminados, H), _)),
             Motivo == acierta,
             last(H, acusacion(Ganador, [S, A, L], acierta)),
             Eliminados == [] )).

test(si_gana_el_ultimo_todos_los_demas_cayeron, [forall(member(N, [3, 4, 5]))]) :-
    length(Tipos, N), maplist(=(azar), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(Ganador, Motivo, partida(_, _, _, Eliminados, _), _)),
             (   Motivo == ultimo
             ->  length(Eliminados, E), E =:= N - 1,
                 \+ memberchk(Ganador, Eliminados)
             ;   true ) )).

test(cada_eliminado_tiene_una_acusacion_fallida_en_el_historial, [forall(member(N, [3, 4, 5]))]) :-
    length(Tipos, N), maplist(=(azar), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(_, _, partida(_, _, _, Eliminados, H), _)),
             forall(member(E, Eliminados), memberchk(acusacion(E, _, falla), H)) )).

test(el_historial_solo_tiene_eventos_publicos, [forall(member(N, [3, 4, 5]))]) :-
    tipos_con_media(N, Tipos),
    forall(between(1, 8, _),
           ( jugar_con(Tipos, fin(_, _, partida(_, _, _, _, H), _)),
             forall(member(E, H), evento_publico(E)) )).

test(nadie_juega_dos_veces_seguidas) :-
    length(Tipos, 4), maplist(=(azar), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(_, _, partida(_, _, _, _, H), _)),
             findall(Q, ( member(E, H), arg(1, E, Q) ), Quienes),
             sin_repetidos_seguidos(Quienes) )).

test(un_eliminado_no_vuelve_a_jugar, [forall(member(N, [3, 4, 5]))]) :-
    length(Tipos, N), maplist(=(azar), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(_, _, partida(_, _, _, _, H), _)),
             nadie_juega_tras_caer(H, []) )).

test(los_turnos_siguen_el_orden_circular, [forall(member(N, [3, 4, 5]))]) :-
    % Cada jugador que juega es el siguiente en círculo (sin eliminados)
    % al anterior, saltando solo a los eliminados.
    length(Tipos, N), maplist(=(azar), Tipos),
    forall(between(1, 15, _),
           ( jugar_con(Tipos, fin(_, _, partida(_, _, _, _, H), _)),
             turnos_en_orden(H, N, [], none) )).

% Quien juega no puede haber caído antes en una acusación fallida.
nadie_juega_tras_caer([], _).
nadie_juega_tras_caer([E|Resto], Caidos) :-
    arg(1, E, Quien),
    \+ memberchk(Quien, Caidos),
    (   E = acusacion(_, _, falla) -> Caidos1 = [Quien|Caidos] ; Caidos1 = Caidos ),
    nadie_juega_tras_caer(Resto, Caidos1).

% Cada turno es del siguiente jugador en círculo que no haya caído.
turnos_en_orden([], _, _, _).
turnos_en_orden([E|Resto], N, Caidos, Anterior) :-
    arg(1, E, Quien),
    (   Anterior == none
    ->  Quien == 1
    ;   Siguiente is Anterior mod N + 1,
        esperado(Siguiente, N, Caidos, Esperado),
        Quien == Esperado
    ),
    (   E = acusacion(_, _, falla) -> Caidos1 = [Quien|Caidos] ; Caidos1 = Caidos ),
    turnos_en_orden(Resto, N, Caidos1, Quien).

esperado(Candidato, N, Caidos, Esperado) :-
    (   memberchk(Candidato, Caidos)
    ->  Otro is Candidato mod N + 1,
        esperado(Otro, N, Caidos, Esperado)
    ;   Esperado = Candidato
    ).

sin_repetidos_seguidos([]).
sin_repetidos_seguidos([_]).
sin_repetidos_seguidos([A, B|Resto]) :- A \== B, sin_repetidos_seguidos([B|Resto]).

:- end_tests(jugar).

:- begin_tests(aplicar_accion).

% Con acciones elegidas a mano se pueden probar los finales que con jugadores
% al azar casi nunca ocurren.

con_facil_en(Turno, P, Js) :-
    partida_en_turno(Turno, [], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js).

test(acertar_termina_la_partida_al_momento) :-
    con_facil_en(2, P, Js),
    aplicar_accion(acusar(senora_coral, cuerda, gimnasio), P, Js, Resultado),
    Resultado = fin(Ganador, Motivo, partida(_, _, _, Eliminados, Historial), _),
    Ganador == 2,
    Motivo == acierta,
    Eliminados == [],
    Historial == [acusacion(2, [senora_coral, cuerda, gimnasio], acierta)].

test(acertar_gana_quien_acusa, [forall(member(Turno, [1, 2, 3, 4]))]) :-
    con_facil_en(Turno, P, Js),
    aplicar_accion(acusar(senora_coral, cuerda, gimnasio), P, Js, fin(Ganador, acierta, _, _)),
    Ganador == Turno.

test(fallar_elimina_y_la_partida_sigue) :-
    con_facil_en(2, P, Js),
    aplicar_accion(acusar(chef_canela, trofeo, cocina), P, Js, fin(_, _, partida(_, _, _, Eliminados, Historial), _)),
    Eliminados = [2|_],
    Historial = [acusacion(2, [chef_canela, trofeo, cocina], falla), _|_].

test(sugerir_registra_la_sugerencia_y_la_partida_sigue) :-
    con_facil_en(1, P, Js),
    aplicar_accion(sugerir(entrenador_cobalto, veneno, revolver), P, Js,
                   fin(_, _, partida(_, _, _, _, Historial), _)),
    Historial = [sugerencia(1, [entrenador_cobalto, veneno, revolver], [refuto(2)]), _|_].

test(tras_sugerir_juega_el_siguiente) :-
    con_facil_en(1, P, Js),
    aplicar_accion(sugerir(entrenador_cobalto, veneno, revolver), P, Js,
                   fin(_, _, partida(_, _, _, _, [_, Segundo|_]), _)),
    arg(1, Segundo, Quien),
    Quien == 2.

test(si_falla_el_penultimo_gana_el_que_queda) :-
    % Quedan el 3 y el 4. El 3 acusa mal: gana el 4 sin jugar más.
    partida_en_turno(3, [1, 2], P),
    jugadores_iniciales(P, [facil, facil, facil, facil], Js),
    aplicar_accion(acusar(chef_canela, trofeo, cocina), P, Js, Resultado),
    Resultado = fin(Ganador, Motivo, partida(_, _, _, Eliminados, Historial), _),
    Ganador == 4,
    Motivo == ultimo,
    Eliminados == [1, 2, 3],
    Historial == [acusacion(3, [chef_canela, trofeo, cocina], falla)].

:- end_tests(aplicar_accion).

:- use_module(library(prolog_xref)).

:- begin_tests(criterio_de_la_issue_10).

test(doscientas_partidas_al_azar_terminan_con_un_ganador, [forall(member(N, [3, 4, 5]))]) :-
    % 70 partidas por cada número de jugadores: 210 en total.
    tipos_variados(N, Tipos),
    forall(between(1, 70, _),
           ( iniciar_partida(Tipos, P, Js),
             jugar(P, Js, Resultado),
             Resultado = fin(Ganador, Motivo, partida(_, Manos, _, Eliminados, H), Js1),
             integer(Ganador), Ganador >= 1, Ganador =< N,
             memberchk(Motivo, [acierta, ultimo]),
             \+ memberchk(Ganador, Eliminados),
             length(Js1, N),
             length(Manos, N),
             H = [_|_] )).

test(partidas_con_la_ia_media_terminan_con_un_ganador, [forall(member(N, [3, 4, 5]))]) :-
    tipos_con_media(N, Tipos),
    forall(between(1, 8, _),
           ( iniciar_partida(Tipos, P, Js),
             jugar(P, Js, fin(Ganador, Motivo, partida(_, _, _, Eliminados, H), Js1)),
             integer(Ganador), Ganador >= 1, Ganador =< N,
             memberchk(Motivo, [acierta, ultimo]),
             \+ memberchk(Ganador, Eliminados),
             length(Js1, N),
             H = [_|_] )).

test(las_partidas_son_distintas_entre_si) :-
    tipos_variados(4, Tipos),
    findall(H, ( between(1, 20, _),
                 iniciar_partida(Tipos, P, Js),
                 jugar(P, Js, fin(_, _, partida(_, _, _, _, H), _)) ),
            Historiales),
    sort(Historiales, Distintos),
    length(Distintos, N),
    N > 15.

test(con_la_misma_semilla_la_partida_se_repite) :-
    tipos_variados(4, Tipos),
    set_random(seed(21)),
    iniciar_partida(Tipos, P1, Js1), jugar(P1, Js1, fin(G1, M1, partida(_, _, _, _, H1), _)),
    set_random(seed(21)),
    iniciar_partida(Tipos, P2, Js2), jugar(P2, Js2, fin(G2, M2, partida(_, _, _, _, H2), _)),
    G1 == G2, M1 == M2, H1 == H2.

% --- El bucle solo habla con los jugadores mediante el protocolo ---

llamadas_de(Modulo, Llamadas) :-
    module_property(Modulo, file(Fichero)),
    xref_source(Fichero, [silent(true)]),
    findall(Nombre/Aridad,
            ( xref_called(Fichero, Objetivo, _),
              callable(Objetivo),
              functor(Objetivo, Nombre, Aridad) ),
            Todas),
    sort(Todas, Llamadas).

exporta(Modulo, Nombre/Aridad) :-
    module_property(Modulo, exports(Exportados)),
    memberchk(Nombre/Aridad, Exportados).

test(el_bucle_no_usa_el_motor_de_deduccion, [forall(member(Modulo, [turnos]))]) :-
    % Deduccion es asunto de cada jugador, no del bucle.
    llamadas_de(Modulo, Llamadas),
    forall(member(Llamada, Llamadas), \+ exporta(deduccion, Llamada)).

test(el_bucle_no_guarda_estado_global) :-
    % xref no registra las llamadas a predicados del sistema (assert, nb_setval...),
    % así que se busca directamente en el código fuente del módulo.
    module_property(turnos, file(Fichero)),
    terminos_del_fichero(Fichero, Terminos),
    forall(member(Prohibida,
                  [assert/1, asserta/1, assertz/1, retract/1, retractall/1,
                   nb_setval/2, b_setval/2, nb_setarg/3, setarg/3]),
           \+ usa_el_predicado(Terminos, Prohibida)).

terminos_del_fichero(Fichero, Terminos) :-
    setup_call_cleanup(
        open(Fichero, read, Flujo),
        leer_todos(Flujo, Terminos),
        close(Flujo)).

leer_todos(Flujo, Terminos) :-
    read_term(Flujo, T, []),
    (   T == end_of_file
    ->  Terminos = []
    ;   Terminos = [T|Resto],
        leer_todos(Flujo, Resto)
    ).

usa_el_predicado(Terminos, Nombre/Aridad) :-
    member(Clausula, Terminos),
    Clausula = (_ :- Cuerpo),
    sub_term(Objetivo, Cuerpo),
    callable(Objetivo),
    functor(Objetivo, Nombre, Aridad).

test(el_bucle_usa_las_operaciones_del_protocolo) :-
    llamadas_de(turnos, Llamadas),
    forall(member(Op, [vista_de/3, elegir_accion/4, elegir_carta_a_mostrar/5,
                       observar_todos/3, observar_a/4]),
           memberchk(Op, Llamadas)).

test(el_bucle_no_llama_a_las_decisiones_internas_de_cada_tipo) :-
    % Las cláusulas elige_accion/5, elige_carta/6 y observa/4 son privadas
    % de jugador.pl: el bucle solo debe conocer las tres operaciones.
    llamadas_de(turnos, Llamadas),
    forall(member(Privada, [elige_accion/5, elige_carta/6, observa/4,
                            accion_al_azar/1, facil_observa/3]),
           \+ memberchk(Privada, Llamadas)).

:- end_tests(criterio_de_la_issue_10).

:- begin_tests(ia_media_en_partidas).

% Jugador 1 media; los demás, del tipo indicado.
contra(N, Rival, Tipos) :-
    Resto is N - 1,
    length(Rivales, Resto), maplist(=(Rival), Rivales),
    Tipos = [media|Rivales].

victorias_de_la_media(Tipos, Partidas, Victorias) :-
    findall(G, ( between(1, Partidas, _),
                 iniciar_partida(Tipos, P, Js),
                 jugar(P, Js, fin(G, _, _, _)) ),
            Ganadores),
    aggregate_all(count, member(1, Ganadores), Victorias).

test(la_ia_media_nunca_es_eliminada, [forall(member(N, [3, 4, 5]))]) :-
    % Contra jugadores al azar, que sí se equivocan al acusar: ella nunca.
    set_random(seed(N)),
    contra(N, azar, Tipos),
    forall(between(1, 6, _),
           ( iniciar_partida(Tipos, P, Js),
             jugar(P, Js, fin(_, _, partida(_, _, _, Eliminados, _), _)),
             \+ memberchk(1, Eliminados) )).

test(la_ia_media_gana_a_los_jugadores_al_azar) :-
    set_random(seed(3)),
    contra(4, azar, Tipos),
    victorias_de_la_media(Tipos, 10, V),
    V >= 9.

test(la_ia_media_gana_a_la_ia_facil) :-
    set_random(seed(4)),
    contra(4, facil, Tipos),
    victorias_de_la_media(Tipos, 10, V),
    V >= 9.

test(la_ia_media_gana_aunque_no_juegue_la_primera) :-
    % La ventaja no viene de la posición: en el puesto 3 también gana.
    set_random(seed(5)),
    forall(between(1, 5, _),
           ( iniciar_partida([facil, facil, media, facil], P, Js),
             jugar(P, Js, fin(G, _, _, _)),
             G == 3 )).

test(la_ia_media_acaba_en_menos_turnos_que_la_facil) :-
    % Mide los eventos del historial: cada sugerencia o acusación es uno.
    set_random(seed(6)),
    eventos_medios([media, facil, facil, facil], 8, ConMedia),
    eventos_medios([facil, facil, facil, facil], 8, SoloFaciles),
    ConMedia < SoloFaciles.

eventos_medios(Tipos, Partidas, Media) :-
    findall(L, ( between(1, Partidas, _),
                 iniciar_partida(Tipos, P, Js),
                 jugar(P, Js, fin(_, _, partida(_, _, _, _, H), _)),
                 length(H, L) ),
            Ls),
    sum_list(Ls, S), length(Ls, N),
    Media is S / N.

:- end_tests(ia_media_en_partidas).

:- begin_tests(termina_si_cae).

% Cuatro jugadores al azar, con el turno y los eliminados que se indiquen.
con_azar(Turno, Eliminados, P, Js) :-
    partida_en_turno(Turno, Eliminados, P),
    jugadores_iniciales(P, [azar, azar, azar, azar], Js).

test(si_ya_esta_eliminado_la_partida_termina_sin_jugar) :-
    con_azar(2, [1], P, Js),
    jugar(P, Js, [termina_si_cae(1)], Resultado),
    Resultado == fin(ninguno, eliminado(1), P, Js).

test(no_hay_ganador_cuando_termina_asi) :-
    con_azar(2, [1], P, Js),
    jugar(P, Js, [termina_si_cae(1)], fin(Ganador, Motivo, _, _)),
    Ganador == ninguno,
    Motivo == eliminado(1).

test(sin_la_opcion_la_partida_sigue_aunque_el_jugador_este_eliminado) :-
    con_azar(2, [1], P, Js),
    jugar(P, Js, fin(Ganador, Motivo, partida(_, _, _, _, H), _)),
    integer(Ganador), Ganador > 1,
    memberchk(Motivo, [acierta, ultimo]),
    H = [_|_].

test(la_opcion_de_otro_jugador_no_afecta, [forall(member(Opcion, [termina_si_cae(3), termina_si_cae(4)]))]) :-
    % Los jugadores 3 y 4 son IAs fáciles, que nunca se equivocan al acusar:
    % la opción de uno de ellos no puede dispararse, y la partida llega al final.
    partida_en_turno(2, [1], P),
    jugadores_iniciales(P, [azar, azar, facil, facil], Js),
    jugar(P, Js, [Opcion], fin(Ganador, Motivo, partida(_, _, _, _, H), _)),
    integer(Ganador),
    memberchk(Motivo, [acierta, ultimo]),
    H = [_|_].

test(con_varias_opciones_vale_cualquiera_de_ellas) :-
    con_azar(2, [3], P, Js),
    jugar(P, Js, [termina_si_cae(1), termina_si_cae(3)], Resultado),
    Resultado = fin(ninguno, eliminado(3), _, _).

test(acusar_mal_con_la_opcion_termina_de_inmediato) :-
    con_azar(1, [], P, Js),
    aplicar_accion(acusar(chef_canela, trofeo, cocina), P, Js, [termina_si_cae(1)], Resultado),
    Resultado = fin(Ganador, Motivo, partida(_, _, _, Eliminados, Historial), _),
    Ganador == ninguno,
    Motivo == eliminado(1),
    Eliminados == [1],
    Historial == [acusacion(1, [chef_canela, trofeo, cocina], falla)].

test(acusar_mal_sin_la_opcion_la_partida_sigue) :-
    con_azar(1, [], P, Js),
    aplicar_accion(acusar(chef_canela, trofeo, cocina), P, Js, Resultado),
    Resultado = fin(Ganador, _, partida(_, _, _, [1|_], Historial), _),
    integer(Ganador),
    Historial = [acusacion(1, _, falla), _|_].

test(acertar_con_la_opcion_gana_como_siempre) :-
    con_azar(1, [], P, Js),
    aplicar_accion(acusar(senora_coral, cuerda, gimnasio), P, Js, [termina_si_cae(1)], Resultado),
    Resultado = fin(Ganador, Motivo, _, _),
    Ganador == 1, Motivo == acierta.

test(sugerir_con_la_opcion_no_termina_la_partida) :-
    con_azar(1, [], P, Js),
    aplicar_accion(sugerir(entrenador_cobalto, veneno, estudio), P, Js, [termina_si_cae(1)], Resultado),
    Resultado = fin(_, _, partida(_, _, _, _, [sugerencia(1, _, _), _|_]), _).

test(otro_jugador_que_acusa_mal_no_termina_la_partida) :-
    % Acusa mal el 2 y la opción es del 1, que es una IA fácil y nunca cae:
    % la partida sigue hasta el final.
    partida_en_turno(2, [], P),
    jugadores_iniciales(P, [facil, azar, azar, azar], Js),
    aplicar_accion(acusar(chef_canela, trofeo, cocina), P, Js, [termina_si_cae(1)], Resultado),
    Resultado = fin(Ganador, _, partida(_, _, _, Eliminados, _), _),
    integer(Ganador),
    memberchk(2, Eliminados).

test(sin_opciones_jugar_3_y_jugar_4_hacen_lo_mismo) :-
    set_random(seed(11)),
    iniciar_partida([azar, facil, azar, facil], P1, Js1), jugar(P1, Js1, R1),
    set_random(seed(11)),
    iniciar_partida([azar, facil, azar, facil], P2, Js2), jugar(P2, Js2, [], R2),
    R1 = fin(G1, M1, partida(_, _, _, E1, H1), _),
    R2 = fin(G2, M2, partida(_, _, _, E2, H2), _),
    G1 == G2, M1 == M2, E1 == E2, H1 == H2.

test(la_partida_nunca_sigue_despues_de_eliminar_al_jugador, [forall(member(N, [3, 4, 5]))]) :-
    % El jugador 1 juega al azar y acusa a veces, casi siempre mal. Tras
    % varios turnos de sugerencias, la opción tiene que seguir activa: en
    % cuanto cae, la partida termina y su acusación es lo último del historial.
    length(Resto, N), Resto = [_|Otros], maplist(=(facil), Otros),
    Tipos = [azar|Otros],
    findall(Cayo,
            ( between(1, 50, _),
              iniciar_partida(Tipos, P, Js),
              jugar(P, Js, [termina_si_cae(1)], fin(G, M, partida(_, _, _, El, H), _)),
              (   memberchk(1, El)
              ->  G == ninguno, M == eliminado(1),
                  last(H, acusacion(1, _, falla)),
                  Cayo = si
              ;   integer(G), Cayo = no
              ) ),
            Resultados),
    length(Resultados, 50),
    aggregate_all(count, member(si, Resultados), Cayeron),
    Cayeron >= 5.                          % que la comprobación no sea vacía

:- end_tests(termina_si_cae).

:- begin_tests(ia_dificil_en_partidas).

% La IA difícil piensa con muestras, así que aquí se juegan pocas partidas;
% la comparación con la media está en tests/dificil_vs_media.pl.

test(la_ia_dificil_nunca_es_eliminada, [forall(member(Rivales, [[azar, azar], [media, facil, azar]]))]) :-
    % Contra jugadores al azar, que sí se equivocan al acusar: ella nunca.
    set_random(seed(11)),
    forall(between(1, 3, _),
           ( iniciar_partida([dificil|Rivales], P, Js),
             jugar(P, Js, fin(_, _, partida(_, _, _, Eliminados, _), _)),
             \+ memberchk(1, Eliminados) )).

test(la_ia_dificil_gana_a_los_jugadores_al_azar) :-
    set_random(seed(12)),
    findall(G, ( between(1, 6, _),
                 iniciar_partida([dificil, azar, azar, azar], P, Js),
                 jugar(P, Js, fin(G, _, _, _)) ),
            Ganadores),
    aggregate_all(count, member(1, Ganadores), V),
    V >= 5.

test(el_historial_de_una_partida_con_dificil_solo_tiene_eventos_publicos) :-
    set_random(seed(13)),
    iniciar_partida([dificil, media, facil], P, Js),
    jugar(P, Js, fin(_, _, partida(_, _, _, _, H), _)),
    forall(member(E, H), evento_publico(E)).

:- end_tests(ia_dificil_en_partidas).
