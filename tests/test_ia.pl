/*  Tests de src/ia.pl: el pensamiento de cada IA.  */

:- use_module(library(plunit)).
:- use_module('../src/juego').
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
