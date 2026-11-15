/*  Tests de src/explicacion.pl: el registro, el metaintérprete y el texto.  */

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module('../src/juego').
:- use_module('../src/deduccion').
:- use_module('../src/explicacion').
:- use_module('../src/jugador').
:- use_module('../src/turnos').

% 3 jugadores de 6 cartas; el sobre es (senora_coral, cuerda, gimnasio).
partida_expl(partida(sobre(senora_coral, cuerda, gimnasio),
                          [ 1-[chef_canela, daga, biblioteca, cocina, piscina, trofeo],
                            2-[entrenador_cobalto, veneno, sala_de_video, comedor, jardin, tijeras],
                            3-[doctora_violeta, jardinero_verde, estudio, bodega, revolver, senorita_perla]
                          ],
                          1, [], [])).

% Un registro armado a mano, para probar una regla cada vez.
reg_de(Obs, registro(0, Obs)).

% Lo que ve el jugador 1 si ocurren los Eventos, uno tras otro.
reg_tras(Eventos, Registro) :-
    partida_expl(P),
    registro_inicial(1, P, R0),
    foldl(reg_evento, Eventos, R0, Registro).

reg_evento(Evento, R0, R) :- registrar(1, Evento, R0, R).

ctx_expl(ctx(1, [2-'Beto', 3-'Cleo'])).

% El texto de una explicación contiene_expl este fragmento.
contiene_expl(Texto, Fragmento) :-
    sub_string(Texto, _, _, _, Fragmento), !.

:- begin_tests(registro_inicial).

test(apunta_mi_mano) :-
    reg_tras([], registro(_, Obs)),
    memberchk(mano(1, [chef_canela, daga, biblioteca, cocina, piscina, trofeo]), Obs).

test(apunta_cuantos_jugadores_hay_y_cuantas_cartas_tiene_cada_uno) :-
    reg_tras([], registro(0, Obs)),
    memberchk(jugadores(3), Obs),
    forall(member(J, [1, 2, 3]), memberchk(cuenta(J, 6), Obs)).

test(no_apunta_las_manos_de_los_demas) :-
    reg_tras([], registro(_, Obs)),
    \+ memberchk(mano(2, _), Obs),
    \+ memberchk(mano(3, _), Obs).

:- end_tests(registro_inicial).

:- begin_tests(registrar).

test(una_sugerencia_sube_el_turno_y_apunta_quien_no_pudo_y_quien_refuto) :-
    reg_tras([sugerencia(2, [trofeo, veneno, jardin], [no_pudo(3), refuto(1)])],
                  registro(T, Obs)),
    T == 1,
    memberchk(no_pudo(1, 2, 3, [trofeo, veneno, jardin]), Obs),
    \+ ( member(refuto(_, _, _, _), Obs) ).        % el que refutó fui yo

test(apunta_la_refutacion_de_otro) :-
    reg_tras([sugerencia(1, [trofeo, veneno, jardin], [refuto(2)])], registro(_, Obs)),
    memberchk(refuto(1, 1, 2, [trofeo, veneno, jardin]), Obs).

test(no_apunta_lo_que_me_pasa_a_mi) :-
    reg_tras([sugerencia(2, [trofeo, veneno, jardin], [no_pudo(1), refuto(3)])],
                  registro(_, Obs)),
    \+ ( member(no_pudo(_, _, 1, _), Obs) ).

test(la_carta_que_me_ensenan_es_del_turno_de_la_sugerencia) :-
    reg_tras([ sugerencia(2, [a1, a2, a3], []),
                    sugerencia(1, [trofeo, veneno, jardin], [refuto(2)]),
                    carta_vista(2, veneno) ],
                  registro(T, Obs)),
    T == 2,
    memberchk(enseno(2, 2, veneno), Obs).

test(una_acusacion_fallida_se_apunta_con_su_turno) :-
    reg_tras([ sugerencia(2, [a1, a2, a3], []),
                    acusacion(3, [chef_canela, daga, estudio], falla) ],
                  registro(T, Obs)),
    T == 2,
    memberchk(fallo(2, 3, [chef_canela, daga, estudio]), Obs).

test(una_acusacion_acertada_solo_sube_el_turno) :-
    reg_tras([acusacion(3, [chef_canela, daga, estudio], acierta)], registro(T, Obs)),
    T == 1,
    \+ ( member(fallo(_, _, _), Obs) ).

test(el_turno_es_el_numero_de_eventos_publicos) :-
    reg_tras([ sugerencia(2, [a1, a2, a3], [no_pudo(3)]),
                    sugerencia(3, [a1, a2, a3], [refuto(1)]),
                    sugerencia(1, [a1, a2, a3], [refuto(2)]),
                    carta_vista(2, veneno),
                    acusacion(2, [a1, a2, a3], falla) ],
                  registro(T, _)),
    T == 4.

:- end_tests(registrar).

:- begin_tests(prueba).

test(lo_que_tengo_en_mano_lo_tengo_yo_y_no_esta_en_el_sobre) :-
    reg_tras([], R),
    prueba(R, tiene(1, daga), por(en_mi_mano, _, _)),
    prueba(R, descartada(daga), por(alguien_la_tiene, _, _)).

test(la_carta_que_me_ensenan_esta_descartada, [true(Arbol = por(alguien_la_tiene, _, [por(me_la_enseno, _, [hecho(enseno(1, 2, veneno))])]))]) :-
    reg_tras([ sugerencia(1, [trofeo, veneno, jardin], [refuto(2)]),
                    carta_vista(2, veneno) ], R),
    prueba(R, descartada(veneno), Arbol).

test(si_alguien_no_pudo_refutar_no_tiene_esas_cartas, [forall(member(C, [a1, a2, a3]))]) :-
    reg_tras([sugerencia(1, [a1, a2, a3], [no_pudo(2), no_pudo(3)])], R),
    prueba(R, no_tiene(2, C), por(no_pudo_refutar, _, [hecho(no_pudo(1, 1, 2, [a1, a2, a3]))])).

test(no_pudo_refutar_no_dice_nada_de_otro_jugador) :-
    reg_tras([sugerencia(1, [a1, a2, a3], [no_pudo(2), refuto(3)])], R),
    \+ prueba(R, no_tiene(3, a1), _).

test(si_refuto_y_no_tiene_dos_de_las_tres_tiene_la_tercera) :-
    reg_tras([ sugerencia(1, [a1, a2, a3], [no_pudo(2), refuto(3)]) ], R0),
    R0 = registro(_, Obs0),
    % antes, el 3 no pudo refutar a1 y a2
    reg_de(Obs, R),
    append([no_pudo(1, 1, 3, [a1, a2, zz])], [refuto(2, 2, 3, [a1, a2, a3])|Obs0], Obs),
    prueba(R, tiene(3, a3), por(refuto_con_la_unica, _, Hijos)),
    length(Hijos, 3).

test(si_solo_sabe_que_no_tiene_una_de_las_tres_no_se_sabe_cual_tiene) :-
    reg_de([ refuto(2, 2, 3, [a1, a2, a3]), no_pudo(1, 1, 3, [a1, x, y]), jugadores(3) ], R),
    \+ prueba(R, tiene(3, a2), _),
    \+ prueba(R, tiene(3, a3), _).

test(quien_tiene_una_carta_no_deja_de_tenerla) :-
    reg_de([ enseno(2, 2, veneno), jugadores(3), mano(1, [daga]) ], R),
    \+ prueba(R, no_tiene(2, veneno), _).

test(si_otro_la_tiene_este_no) :-
    reg_de([ enseno(2, 2, veneno), jugadores(3) ], R),
    prueba(R, no_tiene(3, veneno), por(otro_la_tiene, _, _)).

test(no_se_deduce_que_yo_no_tengo_una_carta_que_si_tengo) :-
    reg_tras([], R),
    \+ prueba(R, no_tiene(1, daga), _).

test(lo_que_no_esta_en_mi_mano_no_lo_tengo) :-
    reg_tras([], R),
    prueba(R, no_tiene(1, veneno), por(no_esta_en_su_mano, _, _)).

test(una_acusacion_fallida_descarta_la_carta_que_queda) :-
    % acusaron a (c, v, s); las dos primeras estan en el sobre; entonces la tercera no
    expl_cartas_menos(sospechoso, chef_canela, Ss),
    expl_cartas_menos(arma, trofeo, As),
    findall(C, ( member(C, Ss) ; member(C, As) ), Mias),
    reg_de([ mano(1, Mias), jugadores(3),
               fallo(5, 2, [chef_canela, trofeo, biblioteca]) ], R),
    prueba(R, descartada(biblioteca), por(acusacion_fallida, _, [hecho(fallo(5, 2, _)), _, _])).

test(una_acusacion_fallida_sola_no_descarta_nada) :-
    reg_de([ mano(1, []), jugadores(3), fallo(5, 2, [chef_canela, trofeo, biblioteca]) ], R),
    \+ prueba(R, descartada(biblioteca), _),
    \+ prueba(R, descartada(trofeo), _).

test(si_nadie_puede_tenerla_esta_en_el_sobre) :-
    reg_de([ mano(1, [daga]), jugadores(3),
               no_pudo(3, 2, 2, [trofeo, x, y]), no_pudo(3, 2, 3, [trofeo, x, y]) ], R),
    prueba(R, en_sobre(trofeo), por(nadie_la_tiene, _, _)).

test(si_la_tengo_yo_no_esta_en_el_sobre_aunque_nadie_mas_la_tenga) :-
    reg_de([ mano(1, [trofeo]), jugadores(3), cuenta(1, 1),
               no_pudo(3, 2, 2, [trofeo, x, y]), no_pudo(3, 2, 3, [trofeo, x, y]) ], R),
    \+ prueba(R, en_sobre(trofeo), _).

test(si_falta_un_jugador_por_descartar_no_esta_en_el_sobre) :-
    reg_de([ mano(1, [daga]), jugadores(3), no_pudo(3, 2, 2, [trofeo, x, y]) ], R),
    \+ prueba(R, en_sobre(trofeo), _).

test(si_todas_las_demas_de_su_tipo_estan_descartadas_esta_en_el_sobre) :-
    expl_cartas_menos(sospechoso, jardinero_verde, Ss),
    reg_de([ mano(1, Ss), jugadores(3), cuenta(1, 5) ], R),
    prueba(R, en_sobre(jardinero_verde), por(la_unica_de_su_tipo, _, _)).

test(si_falta_descartar_una_de_su_tipo_no_se_sabe) :-
    expl_cartas_menos(sospechoso, jardinero_verde, Ss0),
    Ss0 = [_|Ss],
    reg_de([ mano(1, Ss), jugadores(3), cuenta(1, 4) ], R),
    \+ prueba(R, en_sobre(jardinero_verde), _).

test(si_ya_conozco_todas_las_cartas_de_un_jugador_no_tiene_ninguna_mas) :-
    reg_de([ jugadores(3), cuenta(2, 2),
               enseno(1, 2, veneno), enseno(2, 2, daga) ], R),
    prueba(R, no_tiene(2, trofeo), por(conozco_todas_sus_cartas, _, _)),
    \+ prueba(R, no_tiene(2, veneno), por(conozco_todas_sus_cartas, _, _)).

test(cada_jugador_tiene_su_propia_cuenta_de_cartas_conocidas) :-
    reg_de([ jugadores(3), cuenta(2, 1), cuenta(3, 1),
               enseno(1, 2, veneno), enseno(2, 3, daga) ], R),
    prueba(R, no_tiene(2, daga), _),
    prueba(R, no_tiene(3, veneno), _),
    prueba(R, no_tiene(2, trofeo), _),
    prueba(R, no_tiene(3, trofeo), _),
    \+ prueba(R, no_tiene(3, daga), _),
    \+ prueba(R, no_tiene(2, veneno), _).

test(si_conozco_menos_cartas_de_las_que_tiene_no_se_sabe) :-
    reg_de([ jugadores(3), cuenta(2, 3),
               enseno(1, 2, veneno), enseno(2, 2, daga) ], R),
    \+ prueba(R, no_tiene(2, trofeo), _).

test(la_prueba_es_la_mas_corta) :-
    reg_de([ enseno(1, 2, veneno), jugadores(3), mano(1, [daga]) ], R),
    prueba(R, descartada(veneno), por(alguien_la_tiene, _, [por(me_la_enseno, _, [hecho(_)])])).

test(sin_pruebas_posibles_termina_y_falla) :-
    % refutaciones que se necesitan unas a otras: no hay ciclo infinito
    reg_de([ jugadores(3), cuenta(1, 3), cuenta(2, 3), cuenta(3, 3),
               refuto(1, 1, 2, [a1, a2, a3]), refuto(2, 1, 3, [a1, a2, a3]),
               no_pudo(3, 2, 2, [a1, a4, a5]), no_pudo(3, 2, 3, [a2, a4, a6]) ], R),
    \+ prueba(R, en_sobre(a1), _),
    \+ prueba(R, descartada(a1), _).

test(prueba_solo_da_una_respuesta, [nondet]) :-
    reg_tras([], R),
    findall(A, prueba(R, descartada(daga), A), Arboles),
    length(Arboles, 1).

test(el_registro_no_se_modifica) :-
    reg_tras([sugerencia(1, [a1, a2, a3], [no_pudo(2)])], R),
    copy_term(R, R2),
    prueba(R, descartada(daga), _),
    R == R2.

expl_cartas_menos(Tipo, Carta, Cs) :-
    findall(C, ( carta(Tipo, C), C \== Carta ), Cs).

:- end_tests(prueba).

:- begin_tests(texto).

test(explica_una_carta_descartada_citando_el_turno_y_los_nombres) :-
    reg_tras([ sugerencia(2, [a1, a2, a3], []),
                    sugerencia(1, [trofeo, veneno, jardin], [refuto(2)]),
                    carta_vista(2, veneno) ], R),
    ctx_expl(Ctx),
    explicar_carta(R, Ctx, descartada, veneno, Texto),
    contiene_expl(Texto, "turno 2"),
    contiene_expl(Texto, "Beto"),
    contiene_expl(Texto, "Veneno"),
    contiene_expl(Texto, "no puede estar en el sobre").

test(explica_por_que_alguien_no_tiene_una_carta, [nondet]) :-
    reg_tras([ sugerencia(2, [a1, a2, a3], []),
                    sugerencia(2, [senora_coral, cuerda, gimnasio], [no_pudo(3), no_pudo(1)]) ], R),
    ctx_expl(Ctx),
    prueba(R, no_tiene(3, cuerda), Arbol),
    explicar(Ctx, Arbol, Texto),
    contiene_expl(Texto, "Cleo no tiene Cuerda"),
    contiene_expl(Texto, "turno 2"),
    contiene_expl(Texto, "Señora Coral, Cuerda, Gimnasio").

test(habla_en_primera_persona_de_su_mano, [nondet]) :-
    reg_tras([], R),
    ctx_expl(Ctx),
    explicar_carta(R, Ctx, descartada, daga, Texto),
    contiene_expl(Texto, "Daga está en mi mano").

test(sin_nombres_dice_el_jugador_n) :-
    reg_de([ enseno(4, 2, veneno), jugadores(3), mano(1, [daga]) ], R),
    explicar_carta(R, ctx(1, []), descartada, veneno, Texto),
    contiene_expl(Texto, "el jugador 2 me enseñó Veneno").

test(una_prueba_con_pasos_se_explica_con_porque_y_sangria, [nondet]) :-
    expl_sospechosos_menos(Ss),
    reg_de([ mano(1, Ss), jugadores(3), cuenta(1, 5) ], R),
    ctx_expl(Ctx),
    explicar_carta(R, Ctx, en_sobre, jardinero_verde, Texto),
    contiene_expl(Texto, "Jardinero Verde está en el sobre, porque:"),
    contiene_expl(Texto, "\n  - ").

test(explica_las_tres_cartas_de_una_acusacion) :-
    Mias = [chef_canela, entrenador_cobalto, senora_coral, doctora_violeta, senorita_perla,
            trofeo, veneno, daga, revolver, tijeras,
            biblioteca, cocina, sala_de_video, piscina, comedor, estudio, bodega, jardin],
    reg_de([ mano(1, Mias), jugadores(3), cuenta(1, 18) ], R),
    ctx_expl(Ctx),
    explicar_acusacion(R, Ctx, [jardinero_verde, cuerda, gimnasio], Texto),
    contiene_expl(Texto, "Jardinero Verde está en el sobre"),
    contiene_expl(Texto, "Cuerda está en el sobre"),
    contiene_expl(Texto, "Gimnasio está en el sobre").

test(si_no_sabe_explicar_una_carta_lo_dice) :-
    reg_tras([], R),
    ctx_expl(Ctx),
    explicar_acusacion(R, Ctx, [jardinero_verde, cuerda, gimnasio], Texto),
    contiene_expl(Texto, "No sé explicar por qué Jardinero Verde está en el sobre").

test(explicar_carta_falla_si_no_hay_prueba) :-
    reg_tras([], R),
    ctx_expl(Ctx),
    \+ explicar_carta(R, Ctx, en_sobre, cuerda, _).

test(explica_el_conteo_de_cartas_conocidas, [nondet]) :-
    reg_de([ jugadores(3), cuenta(2, 2), enseno(1, 2, veneno), enseno(2, 2, daga) ], R),
    ctx_expl(Ctx),
    prueba(R, no_tiene(2, trofeo), Arbol),
    explicar(Ctx, Arbol, Texto),
    contiene_expl(Texto, "Beto no tiene Trofeo"),
    contiene_expl(Texto, "Beto tiene 2 cartas y ya conozco todas (Veneno, Daga)"),
    contiene_expl(Texto, "turno 1").

expl_sospechosos_menos(Ss) :-
    findall(C, ( carta(sospechoso, C), C \== jardinero_verde ), Ss).

:- end_tests(texto).

:- begin_tests(en_los_jugadores).

test(las_ias_media_y_dificil_empiezan_con_su_registro, [forall(member(Tipo, [media, dificil]))]) :-
    partida_expl(P),
    nuevo_jugador(2, Tipo, P, jugador(2, Tipo, mente(_, _, registro(0, Obs)))),
    memberchk(mano(2, [entrenador_cobalto|_]), Obs).

test(observar_apunta_en_el_registro, [forall(member(Tipo, [media, dificil]))]) :-
    partida_expl(P),
    nuevo_jugador(1, Tipo, P, J0),
    observar(J0, sugerencia(2, [entrenador_cobalto, veneno, estudio], [no_pudo(3)]), J1),
    J1 = jugador(1, Tipo, mente(_, _, registro(1, Obs))),
    memberchk(no_pudo(1, 2, 3, [entrenador_cobalto, veneno, estudio]), Obs).

test(refutar_no_borra_el_registro, [forall(member(Tipo, [media, dificil]))]) :-
    partida_expl(P),
    nuevo_jugador(1, Tipo, P, J0),
    observar(J0, sugerencia(2, [entrenador_cobalto, veneno, estudio], [no_pudo(3)]), J1),
    elegir_carta_a_mostrar(J1, sugerencia(2, [daga, veneno, estudio]), [daga], daga, J2),
    J2 = jugador(1, Tipo, mente(_, _, R)),
    R = registro(1, _).

test(la_ia_facil_y_el_azar_no_cambian, [forall(member(Tipo, [facil, azar]))]) :-
    partida_expl(P),
    nuevo_jugador(1, Tipo, P, J0),
    observar(J0, sugerencia(2, [entrenador_cobalto, veneno, estudio], [no_pudo(3)]), J1),
    J1 = jugador(1, Tipo, M),
    \+ M = mente(_, _, _).

% Una partida entera: el turno del registro es el largo del historial y lo
% que la IA prueba nunca contradice al motor ni al sobre real.
test(en_una_partida_completa_el_registro_cuadra_con_el_historial_y_el_motor,
     [forall(member(Semilla, [1, 2]))]) :-
    set_random(seed(Semilla)),
    iniciar_partida([media, dificil, media], Partida, Jugadores),
    jugar(Partida, Jugadores, fin(_, _, partida(Sobre, _, _, _, Historial), Finales)),
    length(Historial, Turnos),
    Sobre = sobre(S, A, L),
    forall(member(jugador(_, _, mente(K, _, R)), Finales),
           ( R = registro(Turnos, _),
             deducir(K, Estados),
             forall(member(C-E, Estados), expl_de_acuerdo(R, C, E)),
             forall(member(C, [S, A, L]), \+ prueba(R, descartada(C), _)) )).

% Lo que se prueba, el motor lo confirma.
expl_de_acuerdo(R, C, E) :-
    (   prueba(R, en_sobre(C), _) -> E == sobre ; true ),
    (   prueba(R, descartada(C), _) -> E == descartada ; true ).

:- end_tests(en_los_jugadores).
