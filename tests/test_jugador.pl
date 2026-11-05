/*  Tests de src/jugador.pl: los jugadores y su memoria privada.  */

:- use_module(library(plunit)).
:- use_module('../src/juego').
:- use_module('../src/deduccion').
:- use_module('../src/jugador').

% 4 jugadores; las manos de los jugadores 1 y 2 se usan en los tests.
partida_de_prueba(partida(sobre(senora_coral, cuerda, gimnasio),
                          [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                            2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                            3-[doctora_violeta, veneno, estudio, bodega],
                            4-[jardinero_verde, senorita_perla, revolver, tijeras]
                          ],
                          1, [], [])).

:- begin_tests(tipos).

test(hay_cinco_tipos) :-
    findall(T, tipo_de_jugador(T), Tipos),
    Tipos == [humano, facil, media, dificil, azar].

:- end_tests(tipos).

:- begin_tests(nuevo_jugador).

test(el_humano_empieza_sin_memoria, [true(J == jugador(1, humano, []))]) :-
    partida_de_prueba(P),
    nuevo_jugador(1, humano, P, J).

test(la_ia_facil_empieza_viendo_su_mano,
     [true(J == jugador(2, facil, vistas([entrenador_cobalto, trofeo, sala_de_video, comedor, jardin])))]) :-
    partida_de_prueba(P),
    nuevo_jugador(2, facil, P, J).

test(la_ia_media_empieza_con_su_conocimiento, [forall(member(Tipo, [media, dificil]))]) :-
    partida_de_prueba(P),
    nuevo_jugador(3, Tipo, P, jugador(3, Tipo, K)),
    % Lo único que sabe al empezar es su mano: 4 cartas descartadas.
    findall(C, estado_carta(K, C, descartada), Descartadas),
    msort(Descartadas, D),
    msort([doctora_violeta, veneno, estudio, bodega], D).

test(un_tipo_desconocido_da_error, [error(type_error(oneof([humano, facil, media, dificil, azar]), robot))]) :-
    partida_de_prueba(P),
    nuevo_jugador(1, robot, P, _).

:- end_tests(nuevo_jugador).

:- begin_tests(jugadores_iniciales).

test(un_jugador_por_tipo_en_orden) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, dificil], Js),
    Js = [jugador(1, humano, _), jugador(2, facil, _),
          jugador(3, media, _), jugador(4, dificil, _)].

test(con_3_y_con_5_jugadores, [forall(member(N, [3, 5]))]) :-
    nueva_partida(N, P),
    length(Tipos, N), maplist(=(media), Tipos),
    jugadores_iniciales(P, Tipos, Js),
    length(Js, N).

test(faltan_tipos, [error(domain_error(un_tipo_por_jugador(4), [humano, facil]))]) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil], _).

test(sobran_tipos, [error(domain_error(un_tipo_por_jugador(4), _))]) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, dificil, media], _).

test(cada_ia_conoce_solo_lo_suyo) :-
    % La mano del jugador 3 es desconocida para la IA 4, y al revés.
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, media], Js),
    Js = [_, _, jugador(3, _, K3), jugador(4, _, K4)],
    once(estado_carta(K3, veneno, descartada)),
    once(estado_carta(K4, veneno, dudosa)),
    once(estado_carta(K4, tijeras, descartada)),
    once(estado_carta(K3, tijeras, dudosa)).

:- end_tests(jugadores_iniciales).

:- begin_tests(con_memoria).

test(cambia_la_memoria_y_conserva_el_resto,
     [true(J1 == jugador(2, facil, vistas([daga])))]) :-
    con_memoria(jugador(2, facil, vistas([])), vistas([daga]), J1).

:- end_tests(con_memoria).

:- begin_tests(vista).

test(la_vista_solo_tiene_lo_que_el_jugador_puede_ver,
     [true(Vista == vista([doctora_violeta, veneno, estudio, bodega], [], []))]) :-
    partida_de_prueba(P),
    vista_de(3, P, Vista).

test(la_vista_incluye_eliminados_e_historial,
     [true(Vista == vista([chef_canela, daga, biblioteca, cocina, piscina], [4], [algo]))]) :-
    partida_de_prueba(partida(Sobre, Manos, T, _, _)),
    vista_de(1, partida(Sobre, Manos, T, [4], [algo]), Vista).

test(la_vista_no_contiene_el_sobre_ni_las_manos_ajenas) :-
    partida_de_prueba(P),
    vista_de(1, P, Vista),
    \+ sub_term(senora_coral, Vista),
    \+ sub_term(entrenador_cobalto, Vista),
    \+ sub_term(jardinero_verde, Vista).

:- end_tests(vista).

:- begin_tests(protocolo).

vista_vacia(vista([], [], [])).

test(elegir_accion_da_sugerir_o_acusar_con_tres_cartas_validas,
     [forall(member(Tipo, [humano, facil, media, dificil, azar]))]) :-
    partida_de_prueba(P), nuevo_jugador(1, Tipo, P, J),
    vista_vacia(V),
    forall(between(1, 60, _),
           ( elegir_accion(J, V, Accion, _),
             Accion =.. [Que, S, A, L],
             memberchk(Que, [sugerir, acusar]),
             carta(sospechoso, S), carta(arma, A), carta(lugar, L) )).

test(elegir_accion_rechaza_que_le_pasen_la_partida,
     [error(type_error(vista, partida(_, _, _, _, _)))]) :-
    partida_de_prueba(P), nuevo_jugador(1, media, P, J),
    elegir_accion(J, P, _, _).

test(elegir_accion_a_veces_sugiere_y_a_veces_acusa) :-
    set_random(seed(4)),
    partida_de_prueba(P), nuevo_jugador(1, azar, P, J),
    vista_vacia(V),
    findall(Que, ( between(1, 200, _), elegir_accion(J, V, A, _), functor(A, Que, 3) ), Quees),
    memberchk(sugerir, Quees),
    memberchk(acusar, Quees),
    aggregate_all(count, member(sugerir, Quees), NSugerir),
    NSugerir > 150.

test(elegir_carta_ensenia_una_de_las_candidatas,
     [forall(member(Tipo, [humano, facil, media, dificil, azar]))]) :-
    partida_de_prueba(P), nuevo_jugador(2, Tipo, P, J),
    Candidatas = [trofeo, comedor],
    forall(between(1, 40, _),
           ( elegir_carta_a_mostrar(J, sugerencia(1, [chef_canela, trofeo, comedor]),
                                    Candidatas, Carta, _),
             memberchk(Carta, Candidatas) )).

test(con_una_sola_candidata_ensenia_esa, [true(Carta == trofeo)]) :-
    partida_de_prueba(P), nuevo_jugador(2, media, P, J),
    elegir_carta_a_mostrar(J, sugerencia(1, [chef_canela, trofeo, cocina]), [trofeo], Carta, _).

test(las_operaciones_devuelven_al_mismo_jugador_con_su_id_y_tipo,
     [forall(member(Tipo, [humano, facil, media, dificil, azar]))]) :-
    partida_de_prueba(P), nuevo_jugador(2, Tipo, P, J),
    vista_vacia(V),
    elegir_accion(J, V, _, J1),
    J1 = jugador(2, Tipo, _),
    elegir_carta_a_mostrar(J1, sugerencia(1, [a, b, c]), [trofeo], _, J2),
    J2 = jugador(2, Tipo, _),
    observar(J2, sugerencia(1, [chef_canela, trofeo, comedor]), J3),
    J3 = jugador(2, Tipo, _).

:- end_tests(protocolo).

:- begin_tests(eventos).

test(sugerencia_y_acusacion_son_publicas) :-
    evento_publico(sugerencia(1, [chef_canela, trofeo, cocina], [no_pudo(2), refuto(3)])),
    evento_publico(sugerencia(1, [chef_canela, trofeo, cocina], [])),
    evento_publico(acusacion(2, [chef_canela, trofeo, cocina], acierta)),
    evento_publico(acusacion(2, [chef_canela, trofeo, cocina], falla)).

test(el_resultado_de_una_acusacion_tiene_que_ser_acierta_o_falla, [fail]) :-
    evento_publico(acusacion(2, [chef_canela, trofeo, cocina], quizas)).

test(la_carta_enseniada_es_privada) :-
    evento_privado(carta_vista(3, trofeo)),
    \+ evento_publico(carta_vista(3, trofeo)).

test(ningun_evento_es_publico_y_privado) :-
    \+ ( evento_publico(E), evento_privado(E) ).

test(observar_todos_entrega_a_todos_y_conserva_el_orden) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, dificil], Js),
    observar_todos(sugerencia(1, [chef_canela, trofeo, cocina], [refuto(2)]), Js, Js1),
    length(Js1, 4),
    Js1 = [jugador(1, _, _), jugador(2, _, _), jugador(3, _, _), jugador(4, _, _)].

test(no_se_puede_difundir_un_evento_privado,
     [error(domain_error(evento_publico, carta_vista(3, trofeo)))]) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, dificil], Js),
    observar_todos(carta_vista(3, trofeo), Js, _).

test(no_se_puede_entregar_en_privado_un_evento_publico,
     [error(domain_error(evento_privado, acusacion(2, [a, b, c], falla)))]) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, media, dificil], Js),
    observar_a(1, acusacion(2, [a, b, c], falla), Js, _).

test(el_evento_privado_solo_llega_a_su_destinatario) :-
    partida_de_prueba(P),
    jugadores_iniciales(P, [humano, facil, facil, facil], Js),
    % La daga es del jugador 1: ninguno de los otros la conoce al empezar.
    observar_a(3, carta_vista(1, daga), Js, Js1),
    Js1 = [_, jugador(2, facil, vistas(V2)), jugador(3, facil, vistas(V3)), jugador(4, facil, vistas(V4))],
    \+ memberchk(daga, V2),
    memberchk(daga, V3),
    \+ memberchk(daga, V4).

test(la_ia_facil_recuerda_la_carta_que_le_ensenian) :-
    partida_de_prueba(P),
    nuevo_jugador(1, facil, P, J),
    observar(J, carta_vista(2, trofeo), J1),
    J1 = jugador(1, facil, vistas(Vistas)),
    memberchk(trofeo, Vistas),
    length(Vistas, 6).

test(la_ia_facil_no_repite_una_carta_ya_vista) :-
    partida_de_prueba(P),
    nuevo_jugador(1, facil, P, J),
    observar(J, carta_vista(2, trofeo), J1),
    observar(J1, carta_vista(3, trofeo), J2),
    J2 = jugador(1, facil, vistas(Vistas)),
    length(Vistas, 6).

test(los_eventos_publicos_no_cambian_la_memoria_de_la_ia_facil) :-
    partida_de_prueba(P),
    nuevo_jugador(1, facil, P, J),
    observar(J, sugerencia(2, [chef_canela, trofeo, cocina], [no_pudo(3)]), J1),
    J1 == J.

:- end_tests(eventos).
