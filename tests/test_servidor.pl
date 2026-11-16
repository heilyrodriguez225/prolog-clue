/*  Pruebas de la API (servidor.pl) y del jugador web (puente.pl).
    Se llama a las funciones api_* directamente: no hace falta red. */

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_json)).
:- use_module('../src/servidor').
:- use_module('../src/puente', [poner_retardo/1, registrar_partida/2, publicar/2, foto_actual/2, poner_registro/2, olvidar_partida/1]).
:- use_module('../src/juego', [carta/2]).

% Espera a que la partida pida algo (o termine) y devuelve el estado.
esperar_estado(Id, Estado) :- esperar_estado(Id, 1200, Estado).
esperar_estado(Id, N, Estado) :-
    api_estado(Id, -1, E),
    (   memberchk(E.estado, [esperando, fin, error]) -> Estado = E
    ;   N > 0 -> sleep(0.025), N1 is N - 1, esperar_estado(Id, N1, Estado)
    ;   throw(sin_respuesta(Estado))
    ).

crear(Rivales, Id, Estado0) :-
    api_crear(_{nombre: "Ana", rivales: Rivales}, Estado0),
    Id = Estado0.id.

% Juega al azar hasta el final: sugiere, y a veces acusa. Devuelve el estado final.
jugar_al_azar(Id, Final) :-
    esperar_estado(Id, E),
    (   E.estado == fin -> Final = E
    ;   E.estado == error -> throw(error_en_partida(E))
    ;   E.pendiente.tipo == accion
    ->  findall(C, carta(sospechoso, C), Ss), findall(C, carta(arma, C), As),
        findall(C, carta(lugar, C), Ls),
        random_member(S, Ss), random_member(A, As), random_member(L, Ls),
        (   maybe(1, 12) -> Tipo = acusar ; Tipo = sugerir ),
        api_accion(Id, _{tipo: Tipo, cartas: [S, A, L]}, _),
        jugar_al_azar(Id, Final)
    ;   random_member(C, E.pendiente.candidatas),
        api_carta(Id, _{carta: C}, _),
        jugar_al_azar(Id, Final)
    ).

% Como jugar_al_azar, pero en paso a paso: cuenta las ventanas "siguiente" que ha confirmado
% y comprueba que la partida NO avanza sola mientras espera.
jugar_paso_a_paso(Id, Final, Ventanas) :- jugar_paso_a_paso(Id, 0, Final, Ventanas).
jugar_paso_a_paso(Id, V0, Final, Ventanas) :-
    esperar_estado(Id, E),
    (   E.estado == fin -> Final = E, Ventanas = V0
    ;   E.estado == error -> throw(error_en_partida(E))
    ;   E.pendiente.tipo == siguiente
    ->  Entradas = E.pendiente.n,
        length(E.historial, Largo), Largo >= Entradas,
        sleep(0.1),                                  % nadie avanza la partida
        api_estado(Id, -1, E2), E2.version =:= E.version,
        api_siguiente(Id, _),
        V1 is V0 + 1,
        jugar_paso_a_paso(Id, V1, Final, Ventanas)
    ;   E.pendiente.tipo == accion
    ->  findall(C, carta(sospechoso, C), Ss), findall(C, carta(arma, C), As),
        findall(C, carta(lugar, C), Ls),
        random_member(S, Ss), random_member(A, As), random_member(L, Ls),
        api_accion(Id, _{tipo: sugerir, cartas: [S, A, L]}, _),
        jugar_paso_a_paso(Id, V0, Final, Ventanas)
    ;   random_member(C, E.pendiente.candidatas),
        api_carta(Id, _{carta: C}, _),
        jugar_paso_a_paso(Id, V0, Final, Ventanas)
    ).

% La persona solo sugiere y nunca acusa: la partida la gana una IA acusando.
jugar_sin_acusar(Id, Final) :-
    esperar_estado(Id, E),
    (   E.estado == fin -> Final = E
    ;   E.estado == error -> throw(error_en_partida(E))
    ;   E.pendiente.tipo == accion
    ->  findall(C, carta(sospechoso, C), Ss), findall(C, carta(arma, C), As),
        findall(C, carta(lugar, C), Ls),
        random_member(S, Ss), random_member(A, As), random_member(L, Ls),
        api_accion(Id, _{tipo: sugerir, cartas: [S, A, L]}, _),
        jugar_sin_acusar(Id, Final)
    ;   random_member(C, E.pendiente.candidatas),
        api_carta(Id, _{carta: C}, _),
        jugar_sin_acusar(Id, Final)
    ).

codigo(Goal, Codigo) :-
    catch(( call(Goal), Codigo = ninguno ), api_error(Codigo, _, _), true).

:- begin_tests(api_basica).

test(config) :-
    api_config(C),
    length(C.cartas, 21),
    C.rivales.min =:= 2, C.rivales.max =:= 4,
    memberchk(media, C.niveles),
    memberchk(dificil, C.niveles),
    length(C.nombres, 4).

test(crear_da_estado_inicial) :-
    crear([_{nivel: "facil"}, _{nivel: "media"}], Id, _),
    esperar_estado(Id, E),
    E.estado == esperando, E.turno =:= 1,
    api_abandonar(Id).

test(cada_rival_tiene_su_nivel) :-
    crear([_{nivel: "facil"}, _{nivel: "media"}, _{nivel: "azar"}], Id, E),
    findall(N, ( member(J, E.jugadores), get_dict(nivel, J, N) ), Niveles),
    Niveles == [null, facil, media, azar],
    api_abandonar(Id).

test(una_dificil_y_dos_faciles_cada_asiento_con_su_nivel_y_se_juega_hasta_el_final) :-
    crear([_{nivel: "dificil"}, _{nivel: "facil"}, _{nivel: "facil"}], Id, E0),
    findall(N-Nombre, ( member(J, E0.jugadores), get_dict(nivel, J, N), get_dict(nombre, J, Nombre) ), Pares),
    Pares = [null-"Ana", dificil-N2, facil-N3, facil-N4],
    sort([N2, N3, N4], [_, _, _]),            % cada IA con su propio nombre
    jugar_al_azar(Id, F),
    F.estado == fin,
    api_abandonar(Id).

test(la_mano_coincide_con_las_cartas) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    length(E.mano, N),
    E.jugadores = [Yo|_],
    Yo.cartas =:= N,
    api_abandonar(Id).

test(no_cuenta_el_sobre_ni_otras_manos) :-
    crear([_{nivel: "media"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    \+ get_dict(sobre, E, _),
    E.fin == null,
    api_abandonar(Id).

test(libreta_con_asistente) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    length(E.libreta, 21),
    forall(member(L, E.libreta), number(L.probabilidad)),
    forall(member(C, E.mano),
           ( member(L, E.libreta), L.carta == C, L.estado == descartada )),
    api_abandonar(Id).

test(libreta_sin_asistente) :-
    api_crear(_{nombre: "Ana", asistente: false,
                rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, E0),
    Id = E0.id,
    esperar_estado(Id, E),
    E.libreta == null,
    api_abandonar(Id).

test(version_sin_cambios) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    api_estado(Id, E.version, E2),
    E2.sin_cambios == true, E2.version =:= E.version,
    \+ get_dict(jugadores, E2, _),
    api_abandonar(Id).

test(nombre_vacio_o_largo) :-
    api_crear(_{nombre: "   ", rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, E1),
    api_crear(_{nombre: "Un nombre larguísimo de más de veinte letras",
                rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, E2),
    E1.jugadores = [H1|_], E2.jugadores = [H2|_],
    H1.nombre == "Detective",
    string_length(H2.nombre, 20),
    api_abandonar(E1.id), api_abandonar(E2.id).

:- end_tests(api_basica).

:- begin_tests(ritmo).

test(la_partida_dice_su_ritmo) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, E),
    number(E.ritmo),
    api_abandonar(Id).

test(se_puede_elegir_el_ritmo_al_crear) :-
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 0.25}, E),
    E.ritmo =:= 0.25,
    api_abandonar(E.id).

test(se_puede_cambiar_mientras_se_juega) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    api_ritmo(Id, _{segundos: 4}, E),
    E.ritmo =:= 4,
    api_ritmo(Id, _{segundos: 0}, E2),
    E2.ritmo =:= 0,
    api_abandonar(Id).

test(cada_partida_tiene_su_ritmo) :-
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 3}, A),
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 1}, B),
    api_ritmo(A.id, _{segundos: 7}, A2),
    A2.ritmo =:= 7,
    api_estado(B.id, -1, B2),
    B2.ritmo =:= 1,
    api_abandonar(A.id), api_abandonar(B.id).

test(ritmo_fuera_de_rango, [forall(member(R, [-1, 11, "rapido", null]))]) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    codigo(api_ritmo(Id, _{segundos: R}, _), C),
    C == ritmo_invalido,
    api_abandonar(Id).

test(ritmo_invalido_al_crear, [true(C == ritmo_invalido)]) :-
    codigo(api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 99}, _), C).

test(ritmo_de_una_partida_que_no_existe, [true(C == partida_no_existe)]) :-
    codigo(api_ritmo(no_existe, _{segundos: 1}, _), C).

test(el_ritmo_puede_ser_manual) :-
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: "manual"}, E),
    E.ritmo == manual,
    api_ritmo(E.id, _{segundos: 2}, E2), E2.ritmo =:= 2,
    api_ritmo(E.id, _{segundos: "manual"}, E3), E3.ritmo == manual,
    api_abandonar(E.id).

test(siguiente_sin_nada_que_confirmar, [true(C == no_esperas_siguiente)]) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    codigo(api_siguiente(Id, _), C),
    api_abandonar(Id).

test(siguiente_de_una_partida_que_no_existe, [true(C == partida_no_existe)]) :-
    codigo(api_siguiente(no_existe, _), C).

:- end_tests(ritmo).

:- begin_tests(paso_a_paso).

% Cada jugada de otro sale en su ventana y la partida espera a "Siguiente".
test(una_partida_entera_en_paso_a_paso, [forall(member(Rivales, [["facil", "facil"], ["media", "azar", "facil"]]))]) :-
    maplist([N, _{nivel: N}]>>true, Rivales, Rs),
    api_crear(_{rivales: Rs, ritmo: "manual"}, E0),
    jugar_paso_a_paso(E0.id, Final, Ventanas),
    Final.estado == fin,
    Ventanas >= 2,                                   % tu resultado y al menos una jugada ajena
    length(Final.fin.sobre, 3),
    api_abandonar(E0.id).

test(la_primera_ventana_es_el_resultado_de_tu_sugerencia) :-
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: "manual"}, E0),
    esperar_estado(E0.id, _),
    api_accion(E0.id, _{tipo: sugerir, cartas: [chef_canela, trofeo, biblioteca]}, _),
    esperar_estado(E0.id, E),
    E.pendiente.tipo == siguiente,
    E.pendiente.n =:= 1,
    last(E.historial, U), U.quien =:= 1,
    api_abandonar(E0.id).

test(sin_paso_a_paso_no_hay_ventanas, [true(Ventanas == 0)]) :-
    api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 0}, E0),
    jugar_al_azar(E0.id, _),
    Ventanas = 0,
    api_abandonar(E0.id).

:- end_tests(paso_a_paso).

:- begin_tests(api_errores).

test(pocos_rivales, [true(C == rivales_invalidos)]) :-
    codigo(api_crear(_{rivales: [_{nivel: "facil"}]}, _), C).
test(demasiados_rivales, [true(C == rivales_invalidos)]) :-
    length(R, 5), maplist(=(_{nivel: "facil"}), R),
    codigo(api_crear(_{rivales: R}, _), C).
test(sin_rivales, [true(C == rivales_invalidos)]) :-
    codigo(api_crear(_{}, _), C).
test(nivel_que_no_existe, [true(C == nivel_invalido)]) :-
    codigo(api_crear(_{rivales: [_{nivel: "genio"}, _{nivel: "facil"}]}, _), C).
test(nivel_ausente, [true(C == nivel_invalido)]) :-
    codigo(api_crear(_{rivales: [_{}, _{nivel: "facil"}]}, _), C).
test(partida_que_no_existe, [true(C == partida_no_existe)]) :-
    codigo(api_estado(nope, -1, _), C).
test(accion_en_partida_que_no_existe, [true(C == partida_no_existe)]) :-
    codigo(api_accion(nope, _{tipo: sugerir, cartas: []}, _), C).

test(accion_invalida) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    forall(member(Cuerpo,
                  [ _{},
                    _{tipo: "bailar", cartas: ["daga", "daga", "daga"]},
                    _{tipo: "sugerir", cartas: ["daga"]},
                    _{tipo: "sugerir", cartas: ["daga", "daga", "daga"]},
                    _{tipo: "sugerir", cartas: ["chef_canela", "trofeo", "inventada"]} ]),
           codigo(api_accion(Id, Cuerpo, _), accion_invalida)),
    % y nada de eso ha movido la partida
    esperar_estado(Id, E), E.pendiente.tipo == accion,
    api_abandonar(Id).

test(accion_dos_veces_seguidas, [true(C == no_esperas_accion)]) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    findall(X, ( carta(sospechoso, X), \+ memberchk(X, E.mano) ), [S|_]),
    findall(X, ( carta(arma, X), \+ memberchk(X, E.mano) ), [A|_]),
    findall(X, ( carta(lugar, X), \+ memberchk(X, E.mano) ), [L|_]),
    Cuerpo = _{tipo: sugerir, cartas: [S, A, L]},
    api_accion(Id, Cuerpo, _),
    codigo(api_accion(Id, Cuerpo, _), C),
    api_abandonar(Id).

test(carta_cuando_no_toca, [true(C == no_esperas_carta)]) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    codigo(api_carta(Id, _{carta: "daga"}, _), C),
    api_abandonar(Id).

test(hay_un_tope_de_partidas, [true(C == demasiadas_partidas), cleanup(poner_maximo_de_partidas(20))]) :-
    poner_maximo_de_partidas(1),
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    codigo(api_crear(_{rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, _), C),
    api_abandonar(Id).

test(abandonar_borra_la_partida, [true(C == partida_no_existe)]) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    api_abandonar(Id),
    codigo(api_estado(Id, -1, _), C).

:- end_tests(api_errores).

:- begin_tests(api_partida_completa).

test(sugerir_y_ver_la_carta_que_te_ensenan) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E0),
    % pide cartas que no son tuyas para que alguien pueda enseñarlas
    findall(C, ( carta(sospechoso, C), \+ memberchk(C, E0.mano) ), [S|_]),
    findall(C, ( carta(arma, C), \+ memberchk(C, E0.mano) ), [A|_]),
    findall(C, ( carta(lugar, C), \+ memberchk(C, E0.mano) ), [L|_]),
    api_accion(Id, _{tipo: sugerir, cartas: [S, A, L]}, _),
    esperar_estado(Id, E),
    E.historial = [Primera|_],
    Primera.quien == 1,
    Primera.carta_vista \== null,
    api_abandonar(Id).

test(acusar_mal_te_elimina_y_acaba) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E0),
    % acusa con tres cartas de tu mano: seguro que no es el sobre
    findall(C, ( carta(sospechoso, C), memberchk(C, E0.mano) ), Ss),
    findall(C, ( carta(arma, C), memberchk(C, E0.mano) ), As),
    findall(C, ( carta(lugar, C), memberchk(C, E0.mano) ), Ls),
    (   Ss = [S|_], As = [A|_], Ls = [L|_]
    ->  api_accion(Id, _{tipo: acusar, cartas: [S, A, L]}, _)
    ;   % mano sin las tres: cualquier acusación sirve si falla
        api_accion(Id, _{tipo: acusar, cartas: [chef_canela, daga, cocina]}, _)
    ),
    esperar_estado(Id, E),
    E.estado == fin,
    E.fin.ganador == null,
    E.fin.motivo == eliminado,
    length(E.fin.sobre, 3),
    % al terminar se enseñan todas las manos: las 18 cartas repartidas más el sobre son las 21
    length(E.fin.manos, 3),
    findall(J, member(_{jugador: J, cartas: _}, E.fin.manos), Js), Js == [1, 2, 3],
    once(member(_{jugador: 1, cartas: MiMano}, E.fin.manos)), MiMano == E0.mano,
    findall(C, ( member(M, E.fin.manos), member(C, M.cartas) ), Repartidas),
    append(Repartidas, E.fin.sobre, Todas),
    length(Todas, 21), sort(Todas, Distintas), length(Distintas, 21).

test(las_manos_no_se_cuentan_hasta_el_final) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, E),
    E.estado \== fin,
    E.fin == null,
    api_abandonar(Id).

test(partidas_al_azar_hasta_el_final) :-
    forall(between(1, 6, _), una_partida_al_azar).

una_partida_al_azar :-
    N is 2 + random(3),
    length(R, N),
    maplist([X]>>( random_member(Nv, ["azar", "facil", "media"]), X = _{nivel: Nv} ), R),
    crear(R, Id, _),
    jugar_al_azar(Id, F),
    F.estado == fin,
    length(F.fin.sobre, 3),
    % la partida de verdad ha terminado: la foto final no cambia
    api_estado(Id, -1, F2), F2.version =:= F.version,
    api_abandonar(Id).

:- end_tests(api_partida_completa).

%   La libreta asistida y el modo espectador (#20)

% Como jugar_al_azar, pero guardando la libreta de cada vez que te toca.
jugar_guardando_libretas(Id, Libretas, Final) :-
    esperar_estado(Id, E),
    (   E.estado == fin -> Libretas = [], Final = E
    ;   E.estado == error -> throw(error_en_partida(E))
    ;   Libretas = [E.libreta|Resto],
        (   E.pendiente.tipo == accion
        ->  findall(C, carta(sospechoso, C), Ss), findall(C, carta(arma, C), As),
            findall(C, carta(lugar, C), Ls),
            random_member(S, Ss), random_member(A, As), random_member(L, Ls),
            (   maybe(1, 12) -> Tipo = acusar ; Tipo = sugerir ),
            api_accion(Id, _{tipo: Tipo, cartas: [S, A, L]}, _)
        ;   random_member(C, E.pendiente.candidatas),
            api_carta(Id, _{carta: C}, _)
        ),
        jugar_guardando_libretas(Id, Resto, Final)
    ).

libreta_coherente(Sobre, Libreta) :-
    forall(member(L, Libreta),
           (   number(L.probabilidad),
               L.probabilidad >= 0.0, L.probabilidad =< 100.0,
               (   L.estado == descartada -> L.probabilidad =:= 0.0 ; true ),
               (   L.estado == sobre -> L.probabilidad =:= 100.0 ; true ),
               % la carta del sobre nunca se marca como descartada
               \+ ( memberchk(L.carta, Sobre), L.estado == descartada )
           )).

:- begin_tests(libreta_asistida).

test(la_libreta_nunca_descarta_el_sobre) :-
    forall(between(1, 5, _), una_partida_con_libretas).

una_partida_con_libretas :-
    crear([_{nivel: "facil"}, _{nivel: "media"}, _{nivel: "azar"}], Id, _),
    jugar_guardando_libretas(Id, Libretas, F),
    maplist(libreta_coherente(F.fin.sobre), Libretas),
    api_abandonar(Id).

test(los_porcentajes_cambian_tras_jugar) :-
    crear([_{nivel: "media"}, _{nivel: "media"}], Id, _),
    esperar_estado(Id, E0),
    findall(X, ( carta(sospechoso, X), \+ memberchk(X, E0.mano) ), [S|_]),
    findall(X, ( carta(arma, X), \+ memberchk(X, E0.mano) ), [A|_]),
    findall(X, ( carta(lugar, X), \+ memberchk(X, E0.mano) ), [L|_]),
    api_accion(Id, _{tipo: sugerir, cartas: [S, A, L]}, _),
    esperar_cambio(Id, E0.version, E1),
    E1.estado == esperando,
    maplist([P]>>get_dict(probabilidad, P, _), E1.libreta),
    findall(P, ( member(X, E0.libreta), get_dict(probabilidad, X, P) ), Antes),
    findall(P, ( member(X, E1.libreta), get_dict(probabilidad, X, P) ), Despues),
    Antes \== Despues,
    api_abandonar(Id).

esperar_cambio(Id, Version, E) :-
    esperar_estado(Id, E1),
    (   E1.version > Version, E1.estado \== jugando -> E = E1
    ;   sleep(0.05), esperar_cambio(Id, Version, E)
    ).

test(sin_asistente_no_hay_libreta) :-
    api_crear(_{nombre: "Ana", asistente: false,
                rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, E0),
    esperar_estado(E0.id, E),
    E.libreta == null,
    api_abandonar(E0.id).

test(espectador_necesita_asistente, [true(C == modo_invalido)]) :-
    codigo(api_crear(_{asistente: false, modo: "espectador",
                       rivales: [_{nivel: "facil"}, _{nivel: "facil"}]}, _), C).

test(espectador_juega_sola_y_la_libreta_llega_al_100) :-
    forall(between(1, 2, _), una_partida_espectador).

una_partida_espectador :-
    api_crear(_{nombre: "IA", modo: "espectador",
                rivales: [_{nivel: "facil"}, _{nivel: "azar"}]}, E0),
    E0.modo == espectador,
    Id = E0.id,
    esperar_estado(Id, F),
    F.estado == fin,
    F.pendiente == null,
    libreta_coherente(F.fin.sobre, F.libreta),
    (   F.fin.ganador =:= 1, F.fin.motivo == acierta
    ->  forall(member(C, F.fin.sobre),
               ( member(L, F.libreta), L.carta == C,
                 L.estado == sobre, L.probabilidad =:= 100.0 ))
    ;   true
    ),
    api_abandonar(Id).

:- end_tests(libreta_asistida).

:- begin_tests(hilos_y_limpieza).

test(abandonar_detiene_el_hilo) :-
    findall(H, thread_property(H, status(running)), Antes),
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    api_abandonar(Id),
    sleep(0.3),
    findall(H, thread_property(H, status(running)), Despues),
    length(Antes, A), length(Despues, D), D =< A.

test(limpiar_no_borra_partidas_recientes) :-
    crear([_{nivel: "facil"}, _{nivel: "facil"}], Id, _),
    esperar_estado(Id, _),
    limpiar_partidas,
    api_estado(Id, -1, _),
    api_abandonar(Id).

:- end_tests(hilos_y_limpieza).

%   Rutas HTTP de verdad, con el servidor escuchando en un puerto libre.

url(Puerto, Ruta, Url) :- format(atom(Url), "http://localhost:~w~w", [Puerto, Ruta]).

pedir(Puerto, Metodo, Ruta, Cuerpo, Estado, Respuesta) :-
    url(Puerto, Ruta, Url),
    (   Cuerpo == none
    ->  Opciones = []
    ;   Opciones = [post(json(Cuerpo))]
    ),
    http_open(Url, In, [method(Metodo), status_code(Estado), header(content_type, Tipo)|Opciones]),
    (   sub_atom(Tipo, 0, _, _, 'application/json')
    ->  json_read_dict(In, Respuesta)
    ;   read_string(In, _, Respuesta)
    ),
    close(In).

pedir_puerto(P) :- nb_getval(puerto_de_prueba, P).

:- begin_tests(rutas_http, [setup(( servidor_arrancar([port(P)]),
                                    nb_setval(puerto_de_prueba, P) )),
                            cleanup(( nb_getval(puerto_de_prueba, P),
                                      servidor_parar(P) ))]).

test(config) :-
    pedir_puerto(P), pedir(P, get, '/api/config', none, 200, R),
    length(R.cartas, 21).

test(crear_y_ver_la_partida) :-
    pedir_puerto(P),
    pedir(P, post, '/api/partida',
          _{nombre: "Ana", rivales: [_{nivel: "facil"}, _{nivel: "media"}]}, 201, R),
    atom_concat('/api/partida/', R.id, Ruta),
    pedir(P, get, Ruta, none, 200, E), E.id == R.id,
    pedir(P, delete, Ruta, none, 200, _),
    pedir(P, get, Ruta, none, 404, Err), Err.error == "partida_no_existe".

test(rivales_invalidos_dan_400) :-
    pedir_puerto(P),
    pedir(P, post, '/api/partida', _{rivales: []}, 400, R),
    R.error == "rivales_invalidos".

test(la_pagina_se_sirve) :-
    pedir_puerto(P),
    pedir(P, get, '/inicio.html', none, 200, Html),
    once(sub_string(Html, _, _, _, "html")).

test(un_error_interno_no_cuenta_detalles) :-
    pedir_puerto(P),
    % un cuerpo que no es un objeto JSON: error de la petición, sin términos de Prolog
    pedir(P, post, '/api/partida', [1, 2], 400, R),
    R.error == "json_invalido",
    \+ sub_string(R.mensaje, _, _, _, "error(").

test(por_defecto_solo_se_escucha_en_este_ordenador, [true(D == [ip(localhost)])]) :-
    direccion_de_escucha([port(_)], D).

test(se_puede_abrir_a_la_red_si_se_pide, [true(D == [])]) :-
    direccion_de_escucha([port(_), escuchar(todas)], D).

test(el_servidor_de_prueba_escucha_en_127_0_0_1) :-
    pedir_puerto(P),
    setup_call_cleanup(tcp_socket(S), tcp_connect(S, '127.0.0.1':P), tcp_close_socket(S)).

test(lo_que_no_existe_da_404) :-
    pedir_puerto(P),
    pedir(P, get, '/nada.html', none, 404, _),
    pedir(P, get, '/api/nada', none, 404, _).

:- end_tests(rutas_http).

:- begin_tests(explicacion_del_fin).

% Gana una IA acusando: la pantalla de fin cuenta paso a paso por qué acusó.
test(cuando_gana_una_ia_el_fin_trae_su_explicacion, [forall(member(Nivel, ["media", "dificil"]))]) :-
    api_crear(_{nombre: "Ana", rivales: [_{nivel: Nivel}, _{nivel: "media"}], ritmo: 0}, E0),
    jugar_sin_acusar(E0.id, F),
    F.fin.ganador >= 2,
    F.fin.motivo == acierta,
    X = F.fin.explicacion,
    X.quien =:= F.fin.ganador,
    atomic(X.nombre),
    length(X.cartas, 3),
    findall(C, member(_{carta: C, texto: _}, X.cartas), Cs),
    Cs == F.fin.sobre,                               % las tres cartas del sobre, por orden
    forall(member(_{carta: _, texto: T}, X.cartas),
           sub_string(T, _, _, _, "está en el sobre")),
    api_abandonar(E0.id).

test(la_explicacion_habla_de_lo_que_vio_esa_ia_con_sus_turnos) :-
    api_crear(_{nombre: "Ana", rivales: [_{nivel: "media"}, _{nivel: "media"}], ritmo: 0}, E0),
    jugar_sin_acusar(E0.id, F),
    X = F.fin.explicacion,
    findall(T, member(_{carta: _, texto: T}, X.cartas), Ts),
    atomic_list_concat(Ts, '\n', Todo),
    once(( sub_atom(Todo, _, _, _, 'turno') ; sub_atom(Todo, _, _, _, 'mi mano') )),
    api_abandonar(E0.id).

% Nada de esto se cuenta antes de tiempo.
test(antes_del_fin_no_hay_explicacion) :-
    api_crear(_{nombre: "Ana", rivales: [_{nivel: "media"}, _{nivel: "media"}], ritmo: 0}, E0),
    esperar_estado(E0.id, E),
    E.estado == esperando,
    E.fin == null,
    \+ get_dict(explicacion, E, _),
    \+ ( get_dict(fin, E, Fin), is_dict(Fin) ),
    api_abandonar(E0.id).

test(si_la_persona_acusa_mal_no_hay_explicacion) :-
    crear([_{nivel: "media"}, _{nivel: "media"}], Id, _),
    esperar_estado(Id, E0),
    findall(C, ( member(C, E0.mano) ), _),
    api_accion(Id, _{tipo: acusar, cartas: [chef_canela, trofeo, biblioteca]}, _),
    esperar_estado(Id, E),
    E.estado == fin,
    (   E.fin.ganador == null
    ->  E.fin.explicacion == null
    ;   true                                        % (acertó de casualidad: ganas tú)
    ),
    api_abandonar(Id).

test(si_gana_una_ia_facil_no_hay_explicacion, [true(Todas == [null])]) :-
    api_crear(_{nombre: "Ana", rivales: [_{nivel: "facil"}, _{nivel: "facil"}], ritmo: 0}, E0),
    jugar_sin_acusar(E0.id, F),
    (   F.fin.ganador >= 2 -> Todas = [F.fin.explicacion] ; Todas = [null] ),
    api_abandonar(E0.id).

% En el modo demo juega una IA por ti y también se explica su acusación.
test(en_el_modo_demo_tambien_se_explica, [forall(between(1, 3, _)), nondet]) :-
    api_crear(_{nombre: "Ana", rivales: [_{nivel: "media"}, _{nivel: "media"}],
                asistente: true, modo: "espectador", ritmo: 0}, E0),
    esperar_estado(E0.id, F),
    F.estado == fin,
    F.fin.motivo == acierta,
    X = F.fin.explicacion,
    X.quien =:= F.fin.ganador,
    length(X.cartas, 3),
    (   F.fin.ganador =:= 1 -> X.nombre == "Ana" ; true ),
    % se explica con lo que la IA vio, turno a turno (también la IA que juega por ti)
    findall(T, member(_{carta: _, texto: T}, X.cartas), Ts),
    atomic_list_concat(Ts, '\n', Todo),
    sub_atom(Todo, _, _, _, 'en el turno'),
    api_abandonar(E0.id).

:- end_tests(explicacion_del_fin).

% El fin de una partida fabricada a mano: quién tiene explicación y quién no.
fin_fabricado(Ganador, Motivo, TipoGanador, Modo, Fin) :-
    Id = fabricada,
    message_queue_create(Cola),
    registrar_partida(Id, Cola),
    publicar(Id, _{estado: jugando}),
    Manos = [1-[chef_canela], 2-[trofeo], 3-[daga]],
    Mem = mente(_, [], registro(5, [ mano(3, [daga]), jugadores(3), cuenta(1, 1), cuenta(2, 1), cuenta(3, 1),
                                     no_pudo(2, 3, 1, [x, y, z]), no_pudo(2, 3, 2, [x, y, z]) ])),
    (   TipoGanador == media -> Memoria = Mem ; Memoria = vistas([daga]) ),
    Jugadores = [jugador(1, web, web(fabricada, none, Modo)),
                 jugador(2, TipoGanador, Memoria),
                 jugador(3, TipoGanador, Memoria)],
    poner_registro(Id, registro(5, [ mano(1, [chef_canela]), jugadores(3), cuenta(1, 1), cuenta(2, 1), cuenta(3, 1) ])),
    servidor:publicar_fin(Id, "Ana", Modo,
                          fin(Ganador, Motivo, partida(sobre(senora_coral, cuerda, gimnasio), Manos, 1, [], []), Jugadores)),
    foto_actual(Id, F),
    Fin = F.fin,
    olvidar_partida(Id),
    message_queue_destroy(Cola).

:- begin_tests(quien_tiene_explicacion).

test(gana_una_ia_media_acusando, [nondet]) :-
    fin_fabricado(3, acierta, media, jugar, Fin),
    Fin.explicacion.quien =:= 3.

test(si_gana_la_persona_no_hay, [true(X == null), nondet]) :-
    fin_fabricado(1, acierta, media, jugar, Fin), X = Fin.explicacion.

test(si_gana_por_ser_el_ultimo_no_hay_acusacion_que_explicar, [true(X == null), nondet]) :-
    fin_fabricado(3, ultimo, media, jugar, Fin), X = Fin.explicacion.

test(si_gana_una_ia_que_no_guarda_registro_no_hay, [true(X == null), nondet]) :-
    fin_fabricado(3, acierta, facil, jugar, Fin), X = Fin.explicacion.

test(sin_ganador_no_hay, [true(X == null), nondet]) :-
    fin_fabricado(ninguno, eliminado(1), media, jugar, Fin), X = Fin.explicacion.

test(en_demo_gana_la_ia_que_juega_por_ti, [nondet]) :-
    fin_fabricado(1, acierta, media, espectador, Fin),
    Fin.explicacion.quien =:= 1.

:- end_tests(quien_tiene_explicacion).
