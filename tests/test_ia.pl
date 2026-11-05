/*  Tests de src/ia.pl: el pensamiento de cada IA.  */

:- use_module(library(plunit)).
:- use_module(library(clpfd)).
:- use_module('../src/juego').
:- use_module('../src/deduccion').
:- use_module('../src/ia').

% La mano del jugador 1 en las partidas de prueba.
mano_de_prueba([chef_canela, daga, biblioteca, cocina, piscina]).

:- begin_tests(cartas_sin_ver).

test(sin_haber_visto_nada_quedan_todas_las_del_tipo) :-
    cartas_sin_ver(sospechoso, [], Cs), length(Cs, 6),
    cartas_sin_ver(arma, [], As), length(As, 6),
    cartas_sin_ver(lugar, [], Ls), length(Ls, 9).

test(quita_las_cartas_vistas_de_ese_tipo) :-
    mano_de_prueba(Mano),
    cartas_sin_ver(sospechoso, Mano, Cs), length(Cs, 5),
    cartas_sin_ver(arma, Mano, As), length(As, 5),
    cartas_sin_ver(lugar, Mano, Ls), length(Ls, 6).

test(no_incluye_ninguna_carta_vista) :-
    mano_de_prueba(Mano),
    forall(member(Tipo, [sospechoso, arma, lugar]),
           ( cartas_sin_ver(Tipo, Mano, Cs),
             forall(member(C, Cs), \+ memberchk(C, Mano)) )).

test(solo_devuelve_cartas_del_tipo_pedido) :-
    mano_de_prueba(Mano),
    cartas_sin_ver(arma, Mano, As),
    forall(member(A, As), carta(arma, A)).

test(si_se_han_visto_todas_las_de_un_tipo_no_queda_ninguna, [true(Cs == [])]) :-
    findall(C, carta(arma, C), Armas),
    cartas_sin_ver(arma, Armas, Cs).

test(si_se_han_visto_todas_menos_una_queda_esa, [true(Cs == [revolver])]) :-
    findall(C, ( carta(arma, C), C \== revolver ), Vistas),
    cartas_sin_ver(arma, Vistas, Cs).

test(conserva_el_orden_del_mazo) :-
    cartas_sin_ver(sospechoso, [], Cs),
    findall(C, carta(sospechoso, C), Mazo),
    Cs == Mazo.

test(es_determinista) :-
    cartas_sin_ver(lugar, [cocina], _).

:- end_tests(cartas_sin_ver).

:- begin_tests(facil_recordar).

test(recuerda_la_carta_que_le_ensenan, [true(V == [trofeo, daga])]) :-
    facil_recordar(carta_vista(3, trofeo), [daga], V).

test(no_repite_una_carta_ya_vista, [true(V == [trofeo, daga])]) :-
    facil_recordar(carta_vista(2, trofeo), [trofeo, daga], V).

test(ignora_las_sugerencias) :-
    V0 = [daga],
    facil_recordar(sugerencia(2, [chef_canela, trofeo, cocina], [no_pudo(3), refuto(4)]), V0, V),
    V == V0.

test(ignora_las_acusaciones) :-
    V0 = [daga],
    facil_recordar(acusacion(2, [chef_canela, trofeo, cocina], falla), V0, V),
    V == V0.

test(no_deduce_nada_de_un_no_pudo) :-
    % La IA fácil no infiere nada de que alguien no pudiera refutar.
    V0 = [daga],
    facil_recordar(sugerencia(1, [chef_canela, trofeo, cocina], [no_pudo(2), no_pudo(3)]), V0, V),
    V == V0.

test(acumula_varias_cartas, [true(V == [cuerda, trofeo, daga])]) :-
    facil_recordar(carta_vista(2, trofeo), [daga], V1),
    facil_recordar(carta_vista(3, cuerda), V1, V).

:- end_tests(facil_recordar).

:- begin_tests(facil_sugerencia).

test(es_una_sugerencia_con_una_carta_de_cada_tipo) :-
    mano_de_prueba(Mano),
    forall(between(1, 100, _),
           ( facil_sugerencia(Mano, sugerir(S, A, L)),
             carta(sospechoso, S), carta(arma, A), carta(lugar, L) )).

test(nunca_sugiere_una_carta_que_ya_ha_visto) :-
    mano_de_prueba(Mano),
    forall(between(1, 200, _),
           ( facil_sugerencia(Mano, sugerir(S, A, L)),
             \+ memberchk(S, Mano), \+ memberchk(A, Mano), \+ memberchk(L, Mano) )).

test(nunca_sugiere_las_cartas_que_le_han_ensenado) :-
    Vistas = [trofeo, veneno, cuerda, chef_canela, senora_coral, cocina, piscina],
    forall(between(1, 200, _),
           ( facil_sugerencia(Vistas, sugerir(S, A, L)),
             forall(member(C, [S, A, L]), \+ memberchk(C, Vistas)) )).

test(puede_sugerir_cualquiera_de_las_que_no_ha_visto) :-
    % Elige al azar entre todas, no siempre las mismas.
    set_random(seed(9)),
    mano_de_prueba(Mano),
    findall(S-A-L, ( between(1, 400, _), facil_sugerencia(Mano, sugerir(S, A, L)) ), Ss),
    forall(member(Tipo-Pos, [sospechoso-1, arma-2, lugar-3]),
           ( cartas_sin_ver(Tipo, Mano, Sin),
             forall(member(C, Sin),
                    ( member(T, Ss), arg_de_trio(Pos, T, C) )) )).

arg_de_trio(1, S-_-_, S).
arg_de_trio(2, _-A-_, A).
arg_de_trio(3, _-_-L, L).

test(si_solo_queda_una_de_cada_tipo_sugiere_esas, [true(Sug == sugerir(senorita_perla, tijeras, jardin))]) :-
    % Ha visto todas las demás: la sugerencia es exactamente el sobre.
    findall(C, ( carta(Tipo, C),
                 \+ memberchk(C, [senorita_perla, tijeras, jardin]),
                 memberchk(Tipo, [sospechoso, arma, lugar]) ),
            Vistas),
    facil_sugerencia(Vistas, Sug).

test(si_no_queda_ninguna_de_un_tipo_es_un_error, [error(existence_error(carta_sin_ver, arma))]) :-
    findall(C, carta(arma, C), Armas),
    facil_sugerencia(Armas, _).

test(con_la_misma_semilla_sugiere_lo_mismo) :-
    mano_de_prueba(Mano),
    set_random(seed(3)), facil_sugerencia(Mano, S1),
    set_random(seed(3)), facil_sugerencia(Mano, S2),
    S1 == S2.

test(es_determinista) :-
    mano_de_prueba(Mano),
    facil_sugerencia(Mano, _).

:- end_tests(facil_sugerencia).

:- begin_tests(facil_accion).

% Todas las cartas del mazo menos las que se indican: lo que habría visto
% una IA que supiera todo salvo esas.
todas_menos(Excepciones, Vistas) :-
    findall(C, ( carta(_, C), \+ memberchk(C, Excepciones) ), Vistas).

test(si_le_queda_una_de_cada_tipo_acusa, [true(Accion == acusar(senorita_perla, tijeras, jardin))]) :-
    todas_menos([senorita_perla, tijeras, jardin], Vistas),
    facil_accion(Vistas, Accion).

test(acusa_exactamente_con_las_que_no_ha_visto, [forall(member(Sobre,
        [[chef_canela, trofeo, cocina],
         [jardinero_verde, revolver, gimnasio],
         [senora_coral, cuerda, biblioteca]]))]) :-
    todas_menos(Sobre, Vistas),
    facil_accion(Vistas, acusar(S, A, L)),
    [S, A, L] == Sobre.

test(si_en_un_tipo_le_quedan_dos_sugiere) :-
    % Le quedan una sospechosa, un arma... y dos lugares.
    todas_menos([senorita_perla, tijeras, jardin, gimnasio], Vistas),
    forall(between(1, 40, _),
           ( facil_accion(Vistas, Accion),
             Accion = sugerir(S, A, L),
             S == senorita_perla, A == tijeras,
             memberchk(L, [jardin, gimnasio]) )).

test(si_le_quedan_varias_en_todos_los_tipos_sugiere) :-
    forall(between(1, 40, _),
           ( facil_accion([chef_canela, daga, cocina], Accion),
             functor(Accion, sugerir, 3) )).

test(sin_haber_visto_nada_sugiere) :-
    facil_accion([], Accion),
    functor(Accion, sugerir, 3).

test(que_le_quede_una_sola_en_algun_tipo_no_basta) :-
    % Sospechoso y arma seguros, pero con tres lugares posibles.
    todas_menos([senorita_perla, tijeras, jardin, gimnasio, estudio], Vistas),
    forall(between(1, 40, _),
           ( facil_accion(Vistas, Accion), functor(Accion, sugerir, 3) )).

test(la_acusacion_no_depende_del_azar) :-
    todas_menos([senorita_perla, tijeras, jardin], Vistas),
    findall(A, ( between(1, 20, _), facil_accion(Vistas, A) ), Acciones),
    sort(Acciones, [_]).

test(en_partidas_reales_acusa_el_sobre_exacto, [forall(member(N, [3, 4, 5]))]) :-
    % Una IA que ha visto todas las cartas menos las del sobre acierta siempre.
    forall(between(1, 40, _),
           ( nueva_partida(N, partida(sobre(S, A, L), _, _, _, _)),
             todas_menos([S, A, L], Vistas),
             facil_accion(Vistas, Accion),
             Accion == acusar(S, A, L) )).

test(es_determinista_al_acusar) :-
    todas_menos([senorita_perla, tijeras, jardin], Vistas),
    facil_accion(Vistas, _).

:- end_tests(facil_accion).

% ---------------------------------------------------------------------
% IA media

% La partida de la demo: 4 jugadores, la IA media es el jugador 1.
partida_de_la_demo(partida(sobre(senora_coral, cuerda, gimnasio),
                     [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                       2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                       3-[doctora_violeta, veneno, estudio, bodega],
                       4-[jardinero_verde, senorita_perla, revolver, tijeras]
                     ],
                     1, [], [])).

% Partida de 3 jugadores en la que solo importa la mano del jugador 1.
partida_de_tres(partida(sobre(x, y, z),
                        [ 1-[estudio, cuerda, bodega, piscina, tijeras, daga],
                          2-[a1, a2, a3, a4, a5, a6],
                          3-[b1, b2, b3, b4, b5, b6] ],
                        1, [], [])).

conocimiento_de_la_demo(K) :-
    partida_de_la_demo(P),
    conocimiento_inicial(1, P, K).

% ¿Hay algún mundo posible en el que Carta sea de J?
puede_ser_de(conocimiento(_, P), Carta, J) :-
    memberchk(Carta-D, P),
    \+ \+ D #= J.

% ¿Hay algún mundo posible en el que J no tenga ninguna de estas cartas?
puede_no_tener_ninguna(conocimiento(_, P), J, Cartas) :-
    maplist(dueno_en(P), Cartas, Ds),
    \+ \+ maplist(distinto_de(J), Ds).

% Ojo: sin findall, que COPIARÍA las variables con sus restricciones y la
% comprobación se haría sobre copias desconectadas del conocimiento real.
dueno_en(P, Carta, Dueno) :- memberchk(Carta-Dueno, P).

distinto_de(J, D) :- D #\= J.

% ¿Hay algún mundo posible en el que las tres cartas estén en el sobre?
pueden_estar_en_el_sobre(conocimiento(_, P), Cartas) :-
    maplist(dueno_en(P), Cartas, Ds),
    \+ \+ maplist(igual_a(0), Ds).

igual_a(V, D) :- D #= V.

estados(K, Estados) :- deducir(K, Estados0), msort(Estados0, Estados).

:- begin_tests(media_observar).

test(no_pudo_ajeno_descarta_esas_cartas_para_ese_jugador) :-
    conocimiento_de_la_demo(K),
    Cs = [entrenador_cobalto, veneno, estudio],
    media_observar(1, sugerencia(2, Cs, [no_pudo(3)]), K),
    forall(member(C, Cs), \+ puede_ser_de(K, C, 3)),
    % Y otras cartas siguen pudiendo ser del 3.
    puede_ser_de(K, jardin, 3).

test(refuto_ajeno_dice_que_tiene_al_menos_una) :-
    conocimiento_de_la_demo(K),
    Cs = [entrenador_cobalto, veneno, estudio],
    puede_no_tener_ninguna(K, 3, Cs),            % antes podría no tener ninguna
    media_observar(1, sugerencia(2, Cs, [refuto(3)]), K),
    \+ puede_no_tener_ninguna(K, 3, Cs),         % ahora tiene al menos una
    % pero no se sabe cuál: cualquiera de las tres puede serlo
    forall(member(C, Cs), puede_ser_de(K, C, 3)).

test(sugerencia_completa_con_no_pudo_y_refuto) :-
    conocimiento_de_la_demo(K),
    Cs = [entrenador_cobalto, veneno, estudio],
    media_observar(1, sugerencia(4, Cs, [no_pudo(2), refuto(3)]), K),
    forall(member(C, Cs), \+ puede_ser_de(K, C, 2)),
    \+ puede_no_tener_ninguna(K, 3, Cs).

test(carta_vista_dice_de_quien_es) :-
    conocimiento_de_la_demo(K),
    media_observar(1, carta_vista(3, veneno), K),
    once(estado_carta(K, veneno, descartada)),
    puede_ser_de(K, veneno, 3),
    \+ puede_ser_de(K, veneno, 2),
    \+ puede_ser_de(K, veneno, 4).

test(si_sugiere_ella_la_carta_vista_concreta_gana_a_el_tiene_alguna) :-
    % Cuando la propia IA sugiere y alguien refuta, el evento público
    % (refuto) y el privado (carta_vista) dicen lo mismo; basta con el privado.
    conocimiento_de_la_demo(K),
    Cs = [entrenador_cobalto, veneno, estudio],
    media_observar(1, sugerencia(1, Cs, [no_pudo(2), refuto(3)]), K),
    media_observar(1, carta_vista(3, veneno), K),
    \+ puede_ser_de(K, veneno, 2),
    \+ puede_ser_de(K, veneno, 4),
    \+ puede_ser_de(K, entrenador_cobalto, 2).

test(si_refuta_ella_no_aprende_nada_nuevo) :-
    conocimiento_de_la_demo(K),
    estados(K, Antes),
    media_observar(1, sugerencia(2, [chef_canela, veneno, estudio], [refuto(1)]), K),
    estados(K, Despues),
    Antes == Despues.

test(que_ella_misma_no_pudiera_refutar_no_cambia_nada) :-
    conocimiento_de_la_demo(K),
    estados(K, Antes),
    media_observar(1, sugerencia(4, [entrenador_cobalto, veneno, estudio], [no_pudo(1)]), K),
    estados(K, Despues),
    Antes == Despues.

test(una_acusacion_fallida_descarta_la_terna) :-
    conocimiento_de_la_demo(K),
    Cs = [entrenador_cobalto, veneno, estudio],
    pueden_estar_en_el_sobre(K, Cs),
    media_observar(1, acusacion(2, Cs, falla), K),
    \+ pueden_estar_en_el_sobre(K, Cs),
    % Pero no dice cuál de las tres está mal: cada una sola aún puede estar.
    forall(member(C, Cs), once(( posibles_en_sobre(K, Ps), memberchk(C, Ps) ))).

test(una_acusacion_que_acierta_no_se_trata_como_informacion) :-
    conocimiento_de_la_demo(K),
    estados(K, Antes),
    media_observar(1, acusacion(2, [senora_coral, cuerda, gimnasio], acierta), K),
    estados(K, Despues),
    Antes == Despues.

test(los_eventos_que_no_conoce_se_ignoran) :-
    conocimiento_de_la_demo(K),
    estados(K, Antes),
    media_observar(1, algo_raro(1, 2, 3), K),
    estados(K, Despues),
    Antes == Despues.

test(los_eventos_se_acumulan) :-
    conocimiento_de_la_demo(K),
    media_observar(1, carta_vista(2, trofeo), K),
    media_observar(1, carta_vista(3, veneno), K),
    once(estado_carta(K, trofeo, descartada)),
    once(estado_carta(K, veneno, descartada)).

test(eventos_equivalen_a_observaciones_directas) :-
    % El caso mínimo de la issue #7, ahora a partir de eventos.
    partida_de_tres(P),
    conocimiento_inicial(1, P, K),
    media_observar(1, sugerencia(2, [doctora_violeta, veneno, cocina], [no_pudo(3)]), K),
    media_observar(1, sugerencia(2, [senora_coral, revolver, comedor], [no_pudo(3)]), K),
    media_observar(1, sugerencia(3, [entrenador_cobalto, trofeo, jardin], [refuto(2)]), K),
    media_observar(1, carta_vista(2, biblioteca), K),
    media_observar(1, carta_vista(2, senorita_perla), K),
    deducir(K, Estados),
    findall(C, member(C-dudosa, Estados), Dudosas),
    msort(Dudosas, D),
    msort([cocina, comedor, doctora_violeta, revolver, senora_coral, veneno], D).

:- end_tests(media_observar).

:- begin_tests(media_accion).

% La IA de la demo tras los turnos 5 y 7: sabe que el sobre es
% senora_coral, cuerda, gimnasio.
con_el_sobre_deducido(K) :-
    conocimiento_de_la_demo(K),
    media_observar(1, sugerencia(1, [senora_coral, cuerda, biblioteca],
                                 [no_pudo(2), no_pudo(3), no_pudo(4)]), K),
    media_observar(1, sugerencia(1, [chef_canela, daga, gimnasio],
                                 [no_pudo(2), no_pudo(3), no_pudo(4)]), K).

test(sin_saber_nada_sugiere) :-
    conocimiento_de_la_demo(K),
    media_accion(K, Accion),
    functor(Accion, sugerir, 3).

test(acusa_cuando_el_sobre_esta_deducido, [true(Accion == acusar(senora_coral, cuerda, gimnasio))]) :-
    con_el_sobre_deducido(K),
    media_accion(K, Accion).

test(no_acusa_antes_de_estar_segura) :-
    conocimiento_de_la_demo(K),
    media_observar(1, sugerencia(1, [senora_coral, cuerda, biblioteca],
                                 [no_pudo(2), no_pudo(3), no_pudo(4)]), K),
    % Ya sabe el sospechoso y el arma, pero el lugar sigue dudoso.
    media_accion(K, Accion),
    functor(Accion, sugerir, 3).

test(acusa_si_y_solo_si_la_solucion_es_segura) :-
    % media_accion y solucion_segura/2 dicen siempre lo mismo.
    conocimiento_de_la_demo(K1),
    (   solucion_segura(K1, _) -> Seg1 = si ; Seg1 = no ),
    media_accion(K1, A1),
    ( functor(A1, acusar, 3) -> Acusa1 = si ; Acusa1 = no ),
    Seg1 == Acusa1,
    con_el_sobre_deducido(K2),
    (   solucion_segura(K2, _) -> Seg2 = si ; Seg2 = no ),
    media_accion(K2, A2),
    ( functor(A2, acusar, 3) -> Acusa2 = si ; Acusa2 = no ),
    Seg2 == Acusa2.

test(la_acusacion_coincide_con_solucion_segura) :-
    con_el_sobre_deducido(K),
    media_accion(K, acusar(S, A, L)),
    solucion_segura(K, sobre(S, A, L)).

test(solo_sugiere_cartas_que_pueden_estar_en_el_sobre) :-
    conocimiento_de_la_demo(K),
    media_observar(1, carta_vista(2, trofeo), K),
    media_observar(1, carta_vista(3, veneno), K),
    media_observar(1, sugerencia(4, [entrenador_cobalto, cuerda, comedor], [no_pudo(2)]), K),
    posibles_en_sobre(K, Posibles),
    forall(between(1, 20, _),
           ( media_accion(K, sugerir(S, A, L)),
             memberchk(S, Posibles), memberchk(A, Posibles), memberchk(L, Posibles) )).

test(nunca_sugiere_una_carta_que_sabe_que_no_esta_en_el_sobre) :-
    conocimiento_de_la_demo(K),
    media_observar(1, carta_vista(2, trofeo), K),
    media_observar(1, carta_vista(3, veneno), K),
    forall(between(1, 25, _),
           ( media_accion(K, sugerir(S, A, L)),
             \+ memberchk(trofeo, [S, A, L]),
             \+ memberchk(veneno, [S, A, L]),
             % tampoco sus propias cartas
             forall(member(C, [S, A, L]), \+ memberchk(C, [chef_canela, daga, biblioteca, cocina, piscina])) )).

test(una_sugerencia_tiene_una_carta_de_cada_tipo) :-
    conocimiento_de_la_demo(K),
    forall(between(1, 12, _),
           ( media_accion(K, sugerir(S, A, L)),
             carta(sospechoso, S), carta(arma, A), carta(lugar, L) )).

test(no_deja_puntos_de_eleccion) :-
    con_el_sobre_deducido(K),
    media_accion(K, _).

:- end_tests(media_accion).
