/*  Tests de src/deduccion.pl: el motor de deducción de la IA.

    Las partidas están escritas a mano para que cada test sepa
    exactamente qué debe deducirse.
*/

:- use_module(library(plunit)).
:- use_module(library(clpfd)).
:- use_module('../src/juego').
:- use_module('../src/deduccion').

% ---- Partidas de prueba ----------------------------------------------

% La de la demo: 4 jugadores, la IA es el jugador 1.
partida_demo(partida(sobre(senora_coral, cuerda, gimnasio),
                     [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                       2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                       3-[doctora_violeta, veneno, estudio, bodega],
                       4-[jardinero_verde, senorita_perla, revolver, tijeras]
                     ],
                     1, [], [])).

% Solo importan la mano del jugador 1 y cuántas cartas tiene cada uno.
partida_con_mano(Mano, Cuentas, partida(sobre(x, y, z), Manos, 1, [], [])) :-
    Cuentas = [N1|Resto],
    length(Mano, N1),
    findall(J-Relleno,
            ( nth1(I, Resto, N), J is I + 1,
              length(Relleno, N) ),
            Otras),
    Manos = [1-Mano|Otras].

% ---- Ayudas ----------------------------------------------------------

estado(K, Carta, Estado) :- once(estado_carta(K, Carta, Estado)).

aplicar(K, mostro(J, C))      :- mostro(K, J, C).
aplicar(K, refuto(J, Cs))     :- refuto(K, J, Cs).
aplicar(K, no_refuto(J, Cs))  :- no_refuto(K, J, Cs).

aplicar_todas(K, Observaciones) :- maplist(aplicar(K), Observaciones).

% Ojo: para imponer restricciones a una lista hay que usar maplist, nunca
% forall, porque forall deshace las restricciones al terminar.
mostrar(K, J-C) :- mostro(K, J, C).

cartas_con_estado(K, Estado, Cartas) :-
    findall(C, estado_carta(K, C, Estado), Cartas).

:- begin_tests(cuentas).

test(cuentas_de_una_partida, [true(Cuentas == [5, 5, 4, 4])]) :-
    partida_demo(P),
    cuentas(P, Cuentas).

test(cuentas_suman_18, [forall(member(N, [3, 4, 5]))]) :-
    nueva_partida(N, P),
    cuentas(P, Cuentas),
    sum_list(Cuentas, 18).

:- end_tests(cuentas).

:- begin_tests(conocimiento_inicial).

test(al_empezar_solo_conoce_su_mano) :-
    partida_demo(P),
    conocimiento_inicial(1, P, K),
    cartas_con_estado(K, descartada, Descartadas),
    msort(Descartadas, D),
    msort([chef_canela, daga, biblioteca, cocina, piscina], D).

test(el_resto_es_dudoso) :-
    partida_demo(P),
    conocimiento_inicial(1, P, K),
    cartas_con_estado(K, dudosa, Dudosas),
    length(Dudosas, 16).

test(al_empezar_no_hay_solucion_segura, [fail]) :-
    partida_demo(P),
    conocimiento_inicial(1, P, K),
    solucion_segura(K, _).

test(cada_jugador_tiene_su_conocimiento) :-
    partida_demo(P),
    conocimiento_inicial(1, P, K1),
    conocimiento_inicial(2, P, K2),
    % Piscina es del jugador 1: solo la IA 1 lo sabe.
    estado(K1, piscina, descartada),
    estado(K2, piscina, dudosa),
    % Trofeo es del jugador 2: solo la IA 2 lo sabe.
    estado(K2, trofeo, descartada),
    estado(K1, trofeo, dudosa).

:- end_tests(conocimiento_inicial).

:- begin_tests(observaciones).

test(carta_enseniada_queda_descartada) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    mostro(K, 2, entrenador_cobalto),
    estado(K, entrenador_cobalto, descartada).

test(carta_enseniada_a_una_ia_no_cambia_a_otra) :-
    partida_demo(P),
    conocimiento_inicial(1, P, K1),
    conocimiento_inicial(3, P, K3),
    mostro(K1, 2, entrenador_cobalto),
    estado(K1, entrenador_cobalto, descartada),
    estado(K3, entrenador_cobalto, dudosa).

test(no_pudo_refutar_descarta_las_cartas_del_otro) :-
    % Si nadie puede refutar una sugerencia y ninguna carta es mía,
    % la sugerencia es el sobre.
    partida_demo(P), conocimiento_inicial(1, P, K),
    Sugerencia = [senora_coral, cuerda, gimnasio],
    no_refuto(K, 2, Sugerencia),
    no_refuto(K, 3, Sugerencia),
    no_refuto(K, 4, Sugerencia),
    solucion_segura(K, sobre(senora_coral, cuerda, gimnasio)).

test(no_pudo_refutar_pero_queda_algo_por_saber, [fail]) :-
    % Solo dos jugadores sin cartas de la sugerencia: el tercero podría tenerlas.
    partida_demo(P), conocimiento_inicial(1, P, K),
    Sugerencia = [senora_coral, cuerda, gimnasio],
    no_refuto(K, 2, Sugerencia),
    no_refuto(K, 3, Sugerencia),
    solucion_segura(K, _).

test(refutar_sin_ver_la_carta_no_descarta_nada) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    findall(C-E, estado_carta(K, C, E), Antes),
    refuto(K, 3, [senora_coral, veneno, jardin]),
    findall(C-E, estado_carta(K, C, E), Despues),
    Antes == Despues.

test(refutar_sin_ver_la_carta_combinado_con_no_pudo_deduce_la_carta,
     [true(Estado == descartada)]) :-
    % El jugador 3 tiene al menos una de {coral, veneno, jardin}, pero no tiene
    % ni coral ni veneno (la segunda observación): la que tiene es jardin.
    partida_demo(P), conocimiento_inicial(1, P, K),
    refuto(K, 3, [senora_coral, veneno, jardin]),
    no_refuto(K, 3, [senora_coral, veneno, comedor]),
    estado(K, jardin, Estado).

test(al_saber_el_sobre_las_otras_18_quedan_descartadas) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    no_refuto(K, 2, [senora_coral, cuerda, gimnasio]),
    no_refuto(K, 3, [senora_coral, cuerda, gimnasio]),
    no_refuto(K, 4, [senora_coral, cuerda, gimnasio]),
    cartas_con_estado(K, descartada, D),
    length(D, 18).

:- end_tests(observaciones).

:- begin_tests(demo).

% La partida de la demo, turno a turno: la IA solo acusa al final.
turnos_demo([ mostro(2, entrenador_cobalto),
              refuto(3, [senora_coral, veneno, jardin]),
              refuto(4, [doctora_violeta, tijeras, comedor]),
              mostro(2, sala_de_video),
              no_refuto(2, [senora_coral, cuerda, biblioteca]),
              no_refuto(3, [senora_coral, cuerda, biblioteca]),
              no_refuto(4, [senora_coral, cuerda, biblioteca]),
              no_refuto(4, [doctora_violeta, veneno, gimnasio]),
              no_refuto(2, [doctora_violeta, veneno, gimnasio]),
              no_refuto(2, [chef_canela, daga, gimnasio]),
              no_refuto(3, [chef_canela, daga, gimnasio]),
              no_refuto(4, [chef_canela, daga, gimnasio]) ]).

test(la_ia_acierta_el_sobre_al_final) :-
    partida_demo(P), P = partida(Sobre, _, _, _, _),
    conocimiento_inicial(1, P, K),
    turnos_demo(Obs),
    aplicar_todas(K, Obs),
    solucion_segura(K, Acusacion),
    Acusacion == Sobre.

test(no_acusa_antes_de_tiempo) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    turnos_demo(Obs),
    length(Primeras, 6),
    append(Primeras, _, Obs),
    aplicar_todas(K, Primeras),
    \+ solucion_segura(K, _).

:- end_tests(demo).

:- begin_tests(busqueda).

test(puede_estar_en_sobre_al_empezar) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    posibles_en_sobre(K, Posibles),
    length(Posibles, 16).

test(una_carta_propia_no_puede_estar_en_el_sobre, [fail]) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    puede_estar_en_sobre(K, piscina).

test(una_carta_de_otro_no_puede_estar_en_el_sobre, [fail]) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    mostro(K, 2, trofeo),
    puede_estar_en_sobre(K, trofeo).

test(preguntar_no_modifica_el_conocimiento) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    K = conocimiento(_, Modelo),
    pairs_values(Modelo, Duenos),
    maplist(fd_dom, Duenos, Antes),
    forall(carta(_, C), ( puede_estar_en_sobre(K, C) -> true ; true )),
    maplist(fd_dom, Duenos, Despues),
    Antes == Despues.

test(deducir_clasifica_las_21_cartas) :-
    partida_demo(P), conocimiento_inicial(1, P, K),
    deducir(K, Estados),
    length(Estados, 21),
    forall(member(_-E, Estados), memberchk(E, [sobre, descartada, dudosa])).

% El caso mínimo de la issue #7: 5 observaciones que la propagación sola no
% aprovecha, pero la búsqueda sí. Se razona por conteo: ver Issue_07 de las notas.
caso_minimo(K) :-
    partida_con_mano([estudio, cuerda, bodega, piscina, tijeras, daga],
                     [6, 6, 6], P),
    conocimiento_inicial(1, P, K),
    no_refuto(K, 3, [doctora_violeta, veneno, cocina]),
    no_refuto(K, 3, [senora_coral, revolver, comedor]),
    refuto(K, 2, [entrenador_cobalto, trofeo, jardin]),
    mostro(K, 2, biblioteca),
    mostro(K, 2, senorita_perla).

test(caso_minimo_la_propagacion_sola_se_queda_corta) :-
    caso_minimo(K),
    cartas_con_estado(K, dudosa, Dudosas),
    length(Dudosas, 13).

test(caso_minimo_la_busqueda_lo_resuelve) :-
    caso_minimo(K),
    deducir(K, Estados),
    findall(C, member(C-dudosa, Estados), Dudosas),
    msort(Dudosas, D),
    msort([cocina, comedor, doctora_violeta, revolver, senora_coral, veneno], D).

test(caso_minimo_posibles_en_sobre) :-
    caso_minimo(K),
    posibles_en_sobre(K, Posibles),
    msort(Posibles, P),
    msort([cocina, comedor, doctora_violeta, revolver, senora_coral, veneno], P).

test(caso_minimo_coincide_con_la_enumeracion_completa) :-
    caso_minimo(K),
    posibles_en_sobre(K, Posibles),
    % Con solo 24 mundos, se puede contar de verdad.
    K = conocimiento(_, Modelo),
    pairs_values(Modelo, Duenos),
    aggregate_all(count, label(Duenos), 24),
    findall(C, ( carta(_, C), memberchk(C-D, Modelo),
                 \+ \+ ( D #= 0, label(Duenos) ) ),
            EnSobre),
    msort(Posibles, A), msort(EnSobre, B),
    A == B.

:- end_tests(busqueda).

:- begin_tests(la_ia_nunca_se_equivoca).

% Si la IA ve todas las manos de los demás, el sobre es lo único que queda.
test(conociendo_todas_las_manos_deduce_el_sobre, [forall(member(N, [3, 4, 5]))]) :-
    forall(between(1, 15, _),
           ( nueva_partida(N, P),
             P = partida(Sobre, Manos, _, _, _),
             conocimiento_inicial(1, P, K),
             findall(J-C, ( member(J-Mano, Manos), J > 1, member(C, Mano) ), Ajenas),
             maplist(mostrar(K), Ajenas),
             solucion_segura(K, Acusacion),
             Acusacion == Sobre )).

% Con cualquier observación coherente, el sobre real siempre sigue siendo posible.
test(el_sobre_real_nunca_se_descarta, [forall(member(N, [3, 4, 5]))]) :-
    forall(between(1, 15, _),
           ( nueva_partida(N, P),
             P = partida(sobre(S, A, L), Manos, _, _, _),
             conocimiento_inicial(1, P, K),
             % Algunas cartas ajenas enseñadas (no las del sobre).
             findall(J-C, ( member(J-Mano, Manos), J > 1, member(C, Mano) ), Ajenas),
             length(Ajenas, Total), Pocas is Total // 2,
             length(Primeras, Pocas), append(Primeras, _, Ajenas),
             maplist(mostrar(K), Primeras),
             posibles_en_sobre(K, Posibles),
             memberchk(S, Posibles), memberchk(A, Posibles), memberchk(L, Posibles) )).

:- end_tests(la_ia_nunca_se_equivoca).
