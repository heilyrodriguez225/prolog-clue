/*  Sherlog: el servidor HTTP.

    Sirve la página (web/) y una API JSON para jugar. El diseño está en
    PLAN.md §3, "La API web".

    Cada partida corre en su propio hilo. El humano es un jugador de tipo
    web, que espera sus jugadas en una cola; las peticiones HTTP las dejan
    ahí, y leen una foto del estado que la partida va publicando. Ver
    puente.pl.

    Las funciones api_* hacen todo el trabajo y no saben nada de HTTP, así
    que se prueban sin red. Los manejadores de abajo solo traducen entre
    HTTP y ellas.

        ... <- jugador.pl <- turnos.pl <- servidor.pl
*/

:- module(servidor,
          [ servidor_arrancar/1,
            servidor_parar/1,
            api_config/1,
            api_crear/2,
            api_estado/3,
            api_accion/3,
            api_carta/3,
            api_abandonar/1,
            limpiar_partidas/0
          ]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_parameters)).
:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(error)).
:- use_module(juego, [carta/2, nombre/2]).
:- use_module(deduccion, [conocimiento_inicial/3, cuentas/2]).
:- use_module(jugador).
:- use_module(turnos).
:- use_module(puente).
:- use_module(sherlog, [niveles/1]).

:- multifile user:file_search_path/2.
:- dynamic user:file_search_path/2.

% La carpeta web/ está junto a src/.
:- prolog_load_context(directory, Src),
   atomic_list_concat([Src, '/../web'], Relativa),
   absolute_file_name(Relativa, Web),
   asserta(user:file_search_path(sherlog_web, Web)).

:- dynamic partida_/4.      % partida_(Id, Hilo, Cola, UltimaActividad)

nombres_de_ias([ 'Beto', 'Cleo', 'Dani', 'Elena' ]).

minutos_sin_actividad(30).
minutos_tras_el_fin(10).

%   ---------------------------------------------------------------------
%   Errores de la API

api_error(Codigo, Estado, Mensaje) :-
    throw(api_error(Codigo, Estado, Mensaje)).

%   ---------------------------------------------------------------------
%   La API

%!  api_config(-Config) is det.
%
%   Lo que la página necesita saber antes de empezar.

api_config(_{cartas: Cartas, niveles: Niveles, rivales: _{min: 2, max: 4}}) :-
    findall(_{id: Id, nombre: Nombre, tipo: Tipo},
            ( carta(Tipo, Id), nombre(Id, Nombre) ),
            Cartas),
    niveles(Niveles).

%!  api_crear(+Entrada, -Estado) is det.
%
%   Entrada es el diccionario del cuerpo de POST /api/partida.

api_crear(Entrada, Estado) :-
    rivales_de(Entrada, Niveles),
    nombre_de(Entrada, Nombre),
    asistente_de(Entrada, Asistente),
    limpiar_partidas,
    nuevo_id(Id),
    message_queue_create(Cola),
    registrar_partida(Id, Cola),
    thread_create(correr(Id, Nombre, Niveles, Asistente), Hilo, [detached(true)]),
    get_time(Ahora),
    with_mutex(sherlog_servidor, assertz(partida_(Id, Hilo, Cola, Ahora))),
    esperar_primera_foto(Id, Estado).

rivales_de(Entrada, Niveles) :-
    (   get_dict(rivales, Entrada, Rivales), is_list(Rivales)
    ->  true
    ;   api_error(rivales_invalidos, 400, "Hacen falta de 2 a 4 rivales.")
    ),
    length(Rivales, N),
    (   between(2, 4, N)
    ->  true
    ;   api_error(rivales_invalidos, 400, "Hacen falta de 2 a 4 rivales.")
    ),
    maplist(nivel_de, Rivales, Niveles).

nivel_de(Rival, Nivel) :-
    niveles(Validos),
    (   is_dict(Rival),
        get_dict(nivel, Rival, Texto),
        a_atomo(Texto, Nivel),
        memberchk(Nivel, Validos)
    ->  true
    ;   api_error(nivel_invalido, 400, "Cada rival necesita un nivel que exista.")
    ).

nombre_de(Entrada, Nombre) :-
    (   get_dict(nombre, Entrada, Crudo),
        a_cadena(Crudo, Texto),
        normalize_space(string(Limpio), Texto),
        Limpio \== ""
    ->  sub_string(Limpio, 0, _, 0, Limpio),
        string_length(Limpio, L),
        Largo is min(L, 20),
        sub_string(Limpio, 0, Largo, _, Nombre)
    ;   Nombre = "Detective"
    ).

asistente_de(Entrada, Asistente) :-
    (   get_dict(asistente, Entrada, false)
    ->  Asistente = false
    ;   Asistente = true
    ).

nuevo_id(Id) :-
    random_between(0, 16777215, N),
    format(atom(Id), '~|~`0t~16r~6+', [N]),
    (   partida_(Id, _, _, _)
    ->  nuevo_id(Id)
    ;   true
    ).

% La partida se prepara en su hilo (el conocimiento CLP(FD) tiene que vivir
% allí). Se espera a que publique su primera foto.
esperar_primera_foto(Id, Estado) :-
    esperar_primera_foto(Id, 200, Estado).

esperar_primera_foto(Id, Intentos, Estado) :-
    (   foto_actual(Id, Estado),
        get_dict(jugadores, Estado, _)
    ->  true
    ;   Intentos > 0
    ->  sleep(0.025),
        Intentos1 is Intentos - 1,
        esperar_primera_foto(Id, Intentos1, Estado)
    ;   api_error(error_interno, 500, "La partida no ha podido empezar.")
    ).

%!  api_estado(+Id, +Version, -Estado) is det.
%
%   Estado actual de la partida. Si Version (un entero) es la actual, no hay
%   nada nuevo y se devuelve solo eso.

api_estado(Id, Version, Estado) :-
    existe_partida(Id),
    tocar(Id),
    (   foto_actual(Id, Foto)
    ->  true
    ;   api_error(partida_no_existe, 404, "No existe esa partida.")
    ),
    get_dict(version, Foto, Actual),
    (   Version == Actual
    ->  Estado = _{version: Actual, sin_cambios: true}
    ;   Estado = Foto
    ).

%!  api_accion(+Id, +Entrada, -Estado) is det.
%
%   Tu jugada: Entrada es {"tipo": "sugerir"|"acusar", "cartas": [...]}.

api_accion(Id, Entrada, Estado) :-
    existe_partida(Id),
    tocar(Id),
    accion_de(Entrada, Tipo, Cartas),
    (   enviar_jugada(Id, accion, accion(Tipo, Cartas))
    ->  true
    ;   api_error(no_esperas_accion, 409, "Ahora no te toca jugar.")
    ),
    foto_actual(Id, Estado).

accion_de(Entrada, Tipo, Cartas) :-
    (   get_dict(tipo, Entrada, TextoTipo),
        a_atomo(TextoTipo, Tipo),
        memberchk(Tipo, [sugerir, acusar]),
        get_dict(cartas, Entrada, Textos),
        is_list(Textos),
        maplist(a_atomo, Textos, Cartas),
        Accion =.. [Tipo|Cartas],
        accion_valida(Accion)
    ->  true
    ;   api_error(accion_invalida, 400,
                  "Una acción es sugerir o acusar con un sospechoso, un arma y un lugar.")
    ).

%!  api_carta(+Id, +Entrada, -Estado) is det.
%
%   La carta que enseñas al refutar: Entrada es {"carta": "trofeo"}.

api_carta(Id, Entrada, Estado) :-
    existe_partida(Id),
    tocar(Id),
    (   foto_actual(Id, Foto),
        get_dict(pendiente, Foto, Pendiente),
        is_dict(Pendiente),
        get_dict(tipo, Pendiente, carta)
    ->  true
    ;   api_error(no_esperas_carta, 409, "Ahora no tienes que enseñar ninguna carta.")
    ),
    get_dict(candidatas, Pendiente, Candidatas),
    (   get_dict(carta, Entrada, Texto),
        a_atomo(Texto, Carta),
        memberchk(Carta, Candidatas)
    ->  true
    ;   api_error(carta_invalida, 400, "Tienes que enseñar una de tus cartas de la sugerencia.")
    ),
    (   enviar_jugada(Id, carta, carta(Carta))
    ->  true
    ;   api_error(no_esperas_carta, 409, "Ahora no tienes que enseñar ninguna carta.")
    ),
    foto_actual(Id, Estado).

% Deja una jugada en la cola de la partida, solo si la partida espera ese
% tipo de jugada. Se marca como atendida al momento, así que enviarla dos
% veces seguidas no deja una jugada vieja esperando en la cola.
enviar_jugada(Id, Tipo, Mensaje) :-
    with_mutex(sherlog_servidor,
               (   foto_actual(Id, Foto),
                   get_dict(pendiente, Foto, Pendiente),
                   is_dict(Pendiente),
                   get_dict(tipo, Pendiente, Tipo),
                   partida_(Id, _, Cola, _),
                   publicar(Id, _{estado: jugando, pendiente: null}),
                   thread_send_message(Cola, Mensaje)
               )).

%!  api_abandonar(+Id) is det.

api_abandonar(Id) :-
    existe_partida(Id),
    olvidar(Id).

%   ---------------------------------------------------------------------
%   El registro de partidas

existe_partida(Id) :-
    (   partida_(Id, _, _, _)
    ->  true
    ;   api_error(partida_no_existe, 404, "No existe esa partida.")
    ).

tocar(Id) :-
    get_time(Ahora),
    with_mutex(sherlog_servidor,
               (   retract(partida_(Id, Hilo, Cola, _))
               ->  assertz(partida_(Id, Hilo, Cola, Ahora))
               ;   true
               )).

% Detiene el hilo de la partida (si sigue vivo) y borra todo lo suyo.
olvidar(Id) :-
    with_mutex(sherlog_servidor,
               (   retract(partida_(Id, Hilo, Cola, _))
               ->  true
               ;   Hilo = none, Cola = none
               )),
    (   Hilo \== none
    ->  detener_hilo(Hilo)
    ;   true
    ),
    olvidar_partida(Id),
    (   Cola \== none
    ->  catch(message_queue_destroy(Cola), _, true)
    ;   true
    ).

detener_hilo(Hilo) :-
    (   catch(thread_property(Hilo, status(running)), _, fail)
    ->  catch(thread_signal(Hilo, throw(partida_abandonada)), _, true)
    ;   true
    ).

%!  limpiar_partidas is det.
%
%   Borra las partidas abandonadas (mucho tiempo sin tocarlas) y las ya
%   terminadas hace rato.

limpiar_partidas :-
    get_time(Ahora),
    minutos_sin_actividad(Inactiva),
    minutos_tras_el_fin(TrasFin),
    findall(Id,
            ( partida_(Id, _, _, Ultima),
              (   Ahora - Ultima > Inactiva * 60
              ;   foto_actual(Id, Foto),
                  get_dict(estado, Foto, Estado),
                  memberchk(Estado, [fin, error]),
                  Ahora - Ultima > TrasFin * 60
              ) ),
            Viejas),
    forall(member(Id, Viejas), olvidar(Id)).

%   ---------------------------------------------------------------------
%   El hilo de una partida

correr(Id, Nombre, Niveles, Asistente) :-
    catch(partida_completa(Id, Nombre, Niveles, Asistente),
          Error,
          terminar_con_error(Id, Error)).

partida_completa(Id, Nombre, Niveles, Asistente) :-
    iniciar_partida([web|Niveles], Partida, Jugadores0),
    (   Asistente == true
    ->  conocimiento_inicial(1, Partida, K)
    ;   K = none
    ),
    jugador_con_id(1, Jugadores0, Humano0),
    con_memoria(Humano0, web(Id, K), Humano),
    reemplazar_jugador(Jugadores0, Humano, Jugadores),
    foto_inicial(Id, Nombre, Niveles, Partida, K),
    jugar(Partida, Jugadores, [termina_si_cae(1)], Resultado),
    publicar_fin(Id, Resultado).

foto_inicial(Id, Nombre, Niveles, Partida, K) :-
    Partida = partida(_, Manos, _, _, _),
    memberchk(1-Mano, Manos),
    cuentas(Partida, Cuentas),
    nombres_de_ias(Nombres),
    Cuentas = [CartasHumano|CartasIAs],
    findall(_{id: Id1, nombre: NombreIA, nivel: Nivel, cartas: N, eliminado: false},
            ( nth1(I, Niveles, Nivel),
              Id1 is I + 1,
              nth1(I, Nombres, NombreIA),
              nth1(I, CartasIAs, N) ),
            IAs),
    Humano = _{id: 1, nombre: Nombre, nivel: null, cartas: CartasHumano, eliminado: false},
    (   K == none
    ->  Libreta = null
    ;   estados_de_la_libreta(K, Libreta)
    ),
    publicar(Id, _{estado: jugando, turno: 1, jugadores: [Humano|IAs], mano: Mano,
                   historial: [], pendiente: null, libreta: Libreta, fin: null}).

publicar_fin(Id, fin(Ganador, Motivo, Partida, _)) :-
    Partida = partida(sobre(S, A, L), _, _, Eliminados, _),
    (   Ganador == ninguno -> Quien = null ; Quien = Ganador ),
    (   Motivo = eliminado(_) -> Texto = eliminado ; Texto = Motivo ),
    publicar(Id, _{estado: fin, turno: null, pendiente: null,
                   fin: _{ganador: Quien, motivo: Texto, sobre: [S, A, L],
                          eliminados: Eliminados}}).

terminar_con_error(Id, partida_abandonada) :-
    !,
    catch(publicar(Id, _{estado: abandonada, pendiente: null}), _, true).
terminar_con_error(Id, Error) :-
    term_to_atom(Error, Texto),
    catch(publicar(Id, _{estado: error, pendiente: null, mensaje: Texto}), _, true).

%   ---------------------------------------------------------------------
%   Texto y átomos

a_atomo(X, A) :-
    (   string(X) -> atom_string(A, X)
    ;   atom(X)   -> A = X
    ).

a_cadena(X, S) :-
    (   string(X) -> S = X
    ;   atom(X)   -> atom_string(X, S)
    ).

%   ---------------------------------------------------------------------
%   HTTP

:- http_handler(root(api/config), manejar_config, []).
:- http_handler(root(api/partida), manejar_partida,
                [prefix, methods([get, post, delete])]).
:- http_handler(root(.), manejar_archivos, [prefix]).

manejar_config(_) :-
    api_config(Config),
    reply_json_dict(Config).

manejar_partida(Request) :-
    memberchk(method(Metodo), Request),
    (   option(path_info(Info), Request) -> true ; Info = '' ),
    split_string(Info, "/", "", Trozos0),
    exclude(==(""), Trozos0, Trozos),
    catch(responder(Metodo, Trozos, Request, Salida),
          Error,
          salida_de_error(Error, Salida)),
    responder_json(Salida).

responder(post, [], Request, 201-Estado) :-
    !,
    leer_json(Request, Entrada),
    api_crear(Entrada, Estado).
responder(get, [IdTexto], Request, 200-Estado) :-
    !,
    atom_string(Id, IdTexto),
    http_parameters(Request, [version(Version, [integer, default(-1)])]),
    api_estado(Id, Version, Estado).
responder(post, [IdTexto, "accion"], Request, 200-Estado) :-
    !,
    atom_string(Id, IdTexto),
    leer_json(Request, Entrada),
    api_accion(Id, Entrada, Estado).
responder(post, [IdTexto, "carta"], Request, 200-Estado) :-
    !,
    atom_string(Id, IdTexto),
    leer_json(Request, Entrada),
    api_carta(Id, Entrada, Estado).
responder(delete, [IdTexto], _, 200-_{abandonada: true}) :-
    !,
    atom_string(Id, IdTexto),
    api_abandonar(Id).
responder(_, _, _, _) :-
    api_error(ruta_no_existe, 404, "No existe esa ruta.").

leer_json(Request, Entrada) :-
    catch(http_read_json_dict(Request, Entrada),
          _,
          api_error(json_invalido, 400, "El cuerpo no es un JSON válido.")),
    (   is_dict(Entrada)
    ->  true
    ;   api_error(json_invalido, 400, "El cuerpo tiene que ser un objeto JSON.")
    ).

salida_de_error(api_error(Codigo, Estado, Mensaje), Estado-_{error: Codigo, mensaje: Mensaje}) :-
    !.
salida_de_error(Error, 500-_{error: error_interno, mensaje: Texto}) :-
    term_to_atom(Error, Texto).

responder_json(Estado-Dict) :-
    reply_json_dict(Dict, [status(Estado)]).

% La página: todo lo que hay en web/. La raíz lleva a la pantalla de inicio.
manejar_archivos(Request) :-
    (   memberchk(path('/'), Request)
    ->  throw(http_reply(moved('/inicio.html')))
    ;   memberchk(path(Ruta), Request),
        absolute_file_name(sherlog_web('.'), Web, [file_type(directory)]),
        (   catch(http_reply_from_files(Web, [], Request), error(permission_error(_, _, _), _), fail)
        ->  true
        ;   throw(http_reply(not_found(Ruta)))   % no existe, o intenta salirse de web/
        )
    ).

%!  servidor_arrancar(+Opciones) is det.
%
%   Opciones: port(Puerto), retardo(Segundos). Si Puerto queda sin
%   concretar se elige uno libre y se devuelve en la misma variable.

servidor_arrancar(Opciones) :-
    (   memberchk(retardo(Segundos), Opciones)
    ->  poner_retardo(Segundos)
    ;   true
    ),
    memberchk(port(Puerto), Opciones),
    http_server(http_dispatch, [port(Puerto)]).

%!  servidor_parar(+Puerto) is det.

servidor_parar(Puerto) :-
    http_stop_server(Puerto, []).
