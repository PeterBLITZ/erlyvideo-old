%%% @author     Max Lapshin <max@maxidoors.ru>
%%% @copyright  2009 Max Lapshin
%%% @doc        Player module
%%% @reference  See <a href="http://github.com/maxlapshin/erlyvideo" target="_top">http://github.com/maxlapshin/erlyvideo</a> for more information
%%% @end
%%%
%%%
%%% Copyright (c) 2009 Max Lapshin
%%%    This program is free software: you can redistribute it and/or modify
%%%    it under the terms of the GNU Affero General Public License as
%%%    published by the Free Software Foundation, either version 3 of the
%%%    License, or any later version.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%%
%%%---------------------------------------------------------------------------------------

-module(ems_play).
-author('rsaccon@gmail.com').
-author('simpleenigmainc@gmail.com').
-author('luke@codegent.com').
-author('max@maxidoors.ru').

-include("../include/ems.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([play/3, file_dir/0, channel_id/2, normalize_filename/1]).

-behaviour(gen_fsm).
-export([init/1, handle_info/3, code_change/4, handle_event/3, handle_sync_event/4, terminate/3]).
-export([ready/2, stop/2]).


play(Name, StreamId, State) ->
  %   case filelib:is_regular(FileName) of
  %     true ->
  %     _ ->
  %       ems_cluster:subscribe(self(), Name),
  %       NextState = State#ems_fsm{type  = wait},
  %       {next_state, 'WAIT_FOR_DATA', NextState, ?TIMEOUT}
  %     % end
  % end;
  init_file(Name, StreamId, State).
  
  
init_file(Name, StreamId, State) ->
  FileName = filename:join([ems_play:file_dir(), ems_play:normalize_filename(Name)]), 
  case filelib:is_regular(FileName) of
    true -> gen_fsm:start_link(?MODULE, {FileName, StreamId, State, self()}, []);
    _ -> init_mpeg_ts(FileName, StreamId, State)
  end.
  
init_mpeg_ts(FileName,StreamId,  State) ->
  {ok, Re} = re:compile("http://(.*).ts"),
  case re:run(FileName, Re) of
    {match, _Captured} -> mpeg_ts:play(FileName);
    _ -> init_stream(FileName, StreamId, State)
  end.

init_stream(Name, _StreamId, _State) ->
  case ems:get_var(netstream, undefined) of
    undefined -> {notfound};
    NetStreamNode -> case rpc:call(NetStreamNode, rtmp, start, [Name], ?TIMEOUT) of
      {ok, NetStream} ->
        link(NetStream),
        ?D({"Netstream created", NetStream}),
        {ok, NetStream};
      _ ->
        {notfound}
      end
  end.

  
init({FileName, StreamId, #ems_fsm{client_buffer = ClientBuffer} = _State, Parent}) ->
	{ok, IoDev} = file:open(FileName, [read, read_ahead]),
	FileFormat = file_format(FileName),
	case FileFormat:init(#video_player{device = IoDev, 
	                                   file_name = FileName,
	                                   consumer = Parent,
	                                   stream_id = StreamId,
	                                   client_buffer = ClientBuffer,
	                                   format = FileFormat}) of
		{ok, VideoPlayerState} -> 
      {ok, ready, VideoPlayerState#video_player{timer_start = erlang:now()}};
    _HdrError -> 
		  ?D(_HdrError),
		  {error, "Invalid header"}
	end.
	
stop(_, State) ->
  {stop, normal, State}.

ready({client_buffer, ClientBuffer}, State) ->
  {next_state, ready, State#video_player{client_buffer = ClientBuffer}};


ready({start}, #video_player{format = FileFormat, consumer = Consumer, client_buffer = ClientBuffer} = State) ->
  case FileFormat of
    mp4 -> gen_fsm:send_event(Consumer, {metadata, "onMetaData", FileFormat:metadata(State), 1});
    _ -> ok
  end,
	Timer = gen_fsm:start_timer(1, play),
	NextState = State#video_player{timer_ref  = Timer, prepush = ClientBuffer},
	?D({"Player starting with pid", self()}),
  {next_state, ready, NextState};
  
ready({pause}, #video_player{timer_ref = Timer} = State) ->
  ?D("Player paused"),
  gen_fsm:cancel_timer(Timer),
  {next_state, ready, State};

ready({resume}, State) ->
  ?D("Player resumed"),
  {next_state, ready, State#video_player{timer_ref = gen_fsm:start_timer(1, play)}};

ready({seek, Timestamp}, #video_player{timer_ref = Timer, client_buffer = ClientBuffer} = State) ->
  {Pos, NewTimestamp} = seek(State, Timestamp),
  gen_fsm:cancel_timer(Timer),
  % ?D({"Player seek to", Timestamp, Pos, NewTimestamp}),
  {next_state, ready, State#video_player{pos = Pos, ts_prev = NewTimestamp, timer_ref = gen_fsm:start_timer(0, play), playing_from = NewTimestamp, prepush = ClientBuffer}};

ready({stop}, State) ->
  ?D("Player stopping"),
  {stop, normal, State};

ready({timeout, _, play}, #video_player{stream_id = StreamId, format = FileFormat, consumer = Consumer} = State) ->
	case FileFormat:read_frame(State) of
		{ok, done} ->
		  ?D("Video file finished"),
		  gen_fsm:send_event(Consumer, {status, ?NS_PLAY_COMPLETE, 1}),
  		{next_state, ready, State};
		{ok, #video_frame{type = _Type} = Frame, Player} -> 
			TimeStamp = Frame#video_frame.timestamp_abs - State#video_player.ts_prev,
			send(Consumer, Frame#video_frame{timestamp=TimeStamp, streamid = StreamId}),
			{Timeout, Player1} = timeout(Frame, Player),
      % ?D({"Frame", Frame#video_frame.timestamp_abs, Player#video_player.timer_start, TimeStamp, Timeout}),
			NextState = Player1#video_player{
			                  timer_ref = gen_fsm:start_timer(Timeout, play),
											  ts_prev = Frame#video_frame.timestamp_abs,
											  pos = Frame#video_frame.nextpos},
			{next_state, ready, NextState};
		{error, _Reason} ->
			?D({"Ems player stopping", _Reason}),
			{stop, _Reason, State}
	end.

seek(#video_player{frames = FrameTable} = _Player, Timestamp) ->
  Ids = ets:select(FrameTable, ets:fun2ms(fun(#file_frame{id = Id,timestamp = FrameTimestamp, keyframe = true} = Frame) when FrameTimestamp =< Timestamp ->
    {Id, FrameTimestamp}
  end)),
  [Item | _] = lists:reverse(Ids),
  Item.



%%-------------------------------------------------------------------------
%% @spec (FLV_TAG::tuple()) -> any()
%% @doc Convert FLV_Tag into Channel then transmit the Channel and Body
%% @end
%%-------------------------------------------------------------------------

send(Consumer, #video_frame{type = Type, streamid=StreamId,timestamp_abs = TimeStamp,body=Body, raw_body = false} = Frame) when is_binary(Body) ->
	Channel = #channel{id=channel_id(Type, StreamId),timestamp=TimeStamp,length=size(Body),type=Type,stream=StreamId},
	gen_fsm:send_event(Consumer, {send, {Channel, ems_flv:encode(Frame)}});

send(Consumer, #video_frame{type = Type, streamid=StreamId,timestamp_abs = TimeStamp,body=Body}) when is_binary(Body) ->
	Channel = #channel{id=channel_id(Type, StreamId),timestamp=TimeStamp,length=size(Body),type=Type,stream=StreamId},
	gen_fsm:send_event(Consumer, {send, {Channel,Body}}).


% rsaccon: TODO: streams per connections need to be stored and channelId retrieved from stream
% idea: a  process per stream, mnesia RAM table (with streamid as key) contains stream process PID
channel_id(?FLV_TAG_TYPE_META, _StreamId) -> 4;
channel_id(?FLV_TAG_TYPE_VIDEO, _StreamId) -> 5;
channel_id(?FLV_TAG_TYPE_AUDIO, _StreamId) -> 5.
% channel_id(?FLV_TAG_TYPE_AUDIO, _StreamId) -> 6.



%%-------------------------------------------------------------------------
%% @spec () -> FileName::string()
%% @doc retrieves FLV video file folder from application environment
%% @end
%%-------------------------------------------------------------------------	
file_dir() ->
  ems:get_var(file_dir, "/tmp").



normalize_filename(Name) ->
    case filename:extension(Name) of
        ".flv" -> Name;
        ".FLV" -> Name;
        ".mp4" -> Name;
        ".MP4" -> Name;
        ".mov" -> Name;
        _      -> Name ++ ".flv"
    end.
 
file_format(Name) ->
  case filename:extension(Name) of
      ".flv" -> ems_flv;
      ".FLV" -> ems_flv;
      ".mp4" -> mp4;
      ".MP4" -> mp4;
      ".mov" -> mp4
  end.
  
handle_event(Event, StateName, StateData) ->
  ?D({"Unknown event in player", Event, StateName}),
    {stop, {StateName, undefined_event, Event}, StateData}.


handle_sync_event(Event, _From, StateName, StateData) ->
     io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, got_sync_request2]),
    {stop, {StateName, undefined_event, Event}, StateData}.

handle_info({tcp_closed, _Socket}, _StateName,
            #video_player{} = StateData) ->
    error_logger:info_msg("~p Video player lost connection.\n", [self()]),
    {stop, normal, StateData};

handle_info(_Info, StateName, StateData) ->
  ?D({"Unknown info in player", _Info, StateName}),
  {noreply, StateName, StateData}.

terminate(_Reason, _StateName, #video_player{device = IoDev} = _State) ->
  ?D("Video player exit"),
  file:close(IoDev),
  ok.
 
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

%%-------------------------------------------------------------------------
%% @spec (AbsTime::integer(), TimerStart::integer(), ClientBuffer::integer()) -> [TimeOut::integer() | 0]
%% @doc calculates timeout to playback of next FLV Tag 
%% @end
%%-------------------------------------------------------------------------	

timeout(#video_frame{timestamp_abs = AbsTime}, #video_player{timer_start = TimerStart, client_buffer = ClientBuffer, playing_from = PlayingFrom, prepush = Prepush} = Player) ->
  SeekTime = AbsTime - PlayingFrom,
  Timeout = SeekTime - ClientBuffer - trunc(timer:now_diff(now(), TimerStart) / 1000),
  % ?D({"Timeout", Timeout, SeekTime, ClientBuffer, trunc(timer:now_diff(now(), TimerStart) / 1000)}),
  if
  (Prepush > SeekTime) ->
    {0, Player#video_player{prepush = Prepush - SeekTime}};
	(Timeout > 0) -> 
    {Timeout, Player}; 
  true -> 
    {0, Player}
  end.

 
