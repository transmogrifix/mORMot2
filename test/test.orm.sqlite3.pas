/// regression tests for ORM on the SQlite3 engine over Http or WebSockets
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit test.orm.sqlite3;

interface

{$I ..\src\mormot.defines.inc}

{$ifdef ISDELPHIXE}
  // since Delphi XE, we have unit System.RegularExpressionsAPI available
  {.$define TEST_REGEXP}
  { TODO : refactor RegExp support to use regexp.c }
{$else}
  // define only if you have unit PCRE.pas installed (not set by default)
  {.$define TEST_REGEXP}
{$endif ISDELPHIXE}

uses
  sysutils,
  contnrs,
  classes,
  {$ifndef FPC}
  typinfo, // to avoid Delphi inlining problems
  {$ifdef ISDELPHI2010} // Delphi 2009/2010 generics are buggy
  Generics.Collections,
  {$endif ISDELPHI2010}
  {$endif FPC}
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.unicode,
  mormot.core.datetime,
  mormot.core.rtti,
  mormot.core.crypto,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.log,
  mormot.core.perf,
  mormot.core.search,
  mormot.core.mustache,
  mormot.core.test,
  mormot.core.interfaces,
  mormot.core.jwt,
  mormot.net.client,
  mormot.net.server,
  mormot.net.relay,
  mormot.net.ws.core,
  mormot.net.ws.client,
  mormot.net.ws.server,
  mormot.db.core,
  mormot.db.nosql.bson,
  mormot.orm.core,
  mormot.orm.rest,
  mormot.orm.storage,
  mormot.orm.sqlite3,
  mormot.orm.client,
  mormot.orm.server,
  mormot.soa.core,
  mormot.soa.server,
  mormot.rest.core,
  mormot.rest.client,
  mormot.rest.server,
  mormot.rest.memserver,
  mormot.rest.sqlite3,
  mormot.rest.http.client,
  mormot.rest.http.server,
  mormot.db.raw.sqlite3,
  mormot.db.raw.sqlite3.static,
  test.core.data,
  test.core.base,
  test.orm.core;

type
  /// a parent test case which will test most functions, classes and types defined
  // and implemented in the mORMotSQLite3 unit, i.e. the SQLite3 engine itself
  // - it should not be called directly, but through TTestFileBased,
  // TTestMemoryBased and TTestMemoryBased children
  TTestSQLite3Engine = class(TSynTestCase)
  protected
    { these values are used internaly by the published methods below }
    BackupProgressStep: TOnSQLDatabaseBackupStep; // should be the first
    TempFileName: TFileName;
    EncryptedFile: boolean;
    Demo: TSQLDataBase;
    Req: RawUTF8;
    JS: RawUTF8;
    BackupTimer: TPrecisionTimer;
    function OnBackupProgress(Sender: TSQLDatabaseBackupThread): boolean;
  published
    /// test direct access to the SQLite3 engine
    // - i.e. via TSQLDataBase and TSQLRequest classes
    procedure DatabaseDirectAccess;
    /// test direct access to the Virtual Table features of SQLite3
    procedure VirtualTableDirectAccess;
    /// test the TOrmTableJSON table
    // - the JSON content generated must match the original data
    // - a VACCUM is performed, for testing some low-level SQLite3 engine
    // implementation
    // - the SortField feature is also tested
    procedure _TOrmTableJSON;
    /// test the TRestClientDB, i.e. a local Client/Server driven usage
    // of the framework
    // - validates TOrmModel, TRestServer and TRestStorage by checking
    // the coherency of the data between client and server instances, after
    // update from both sides
    // - use all RESTful commands (GET/UDPATE/POST/DELETE...)
    // - test the 'many to many' features (i.e. TOrmMany) and dynamic
    // arrays published properties handling
    // - test dynamic tables
    procedure _TRestClientDB;
    {$ifdef TEST_REGEXP}
    /// check the PCRE-based REGEX function
    procedure RegexpFunction;
    {$endif TEST_REGEXP}
    /// test Master/Slave replication using TRecordVersion field
    procedure _TRecordVersion;
  end;

  /// this test case will test most functions, classes and types defined and
  // implemented in the mORMotSQLite3 unit, i.e. the SQLite3 engine itself,
  // with a file-based approach
  TTestFileBased = class(TTestSQLite3Engine);

  /// this test case will test most functions, classes and types defined and
  // implemented in the mORMotSQLite3 unit, i.e. the SQLite3 engine itself,
  // with a file-based approach
  // - purpose of this class is to test Write-Ahead Logging for the database
  TTestFileBasedWAL = class(TTestFileBased);

  /// this test case will test most functions, classes and types defined and
  // implemented in the mORMotSQLite3 unit, i.e. the SQLite3 engine itself,
  // with a file-based approach
  // - purpose of this class is to test Memory-Mapped I/O for the database
  TTestFileBasedMemoryMap = class(TTestFileBased);

  /// this test case will test most functions, classes and types defined and
  // implemented in the mORMotSQLite3 unit, i.e. the SQLite3 engine itself,
  // with a memory-based approach
  // - this class will also test the TRestStorage class, and its
  // 100% Delphi simple database engine
  TTestMemoryBased = class(TTestSQLite3Engine)
  protected
    function CreateShardDB(maxshard: Integer): TRestServer;
  published
    /// test the TOrmTableWritable table
    procedure _TOrmTableWritable;
    /// validate RTREE virtual tables
    procedure _RTree;
    /// validate TRestStorageShardDB add operation, with or without batch
    procedure ShardWrite;
    /// validate TRestStorageShardDB reading among all sharded databases
    procedure ShardRead;
    /// validate TRestStorageShardDB reading after deletion of several shards
    procedure ShardReadAfterPurge;
    /// validate TRestStorageShardDB.MaxShardCount implementation
    procedure _MaxShardCount;
  end;


  /// SOA callback definition as expected by TTestBidirectionalRemoteConnection
  IBidirCallback = interface(IInvokable)
    ['{5C5818CC-FFBA-445C-82C1-39F45B84520C}']
    procedure AsynchEvent(a: integer);
    function Value: Integer;
  end;

  /// SOA service definition as expected by TTestBidirectionalRemoteConnection
  IBidirService = interface(IInvokable)
    ['{0984A2DA-FD1F-49D6-ACFE-4D45CF08CA1B}']
    function TestRest(a, b: integer; out c: RawUTF8): variant;
    function TestRestCustom(a: integer): TServiceCustomAnswer;
    function TestCallback(d: Integer; const callback: IBidirCallback): boolean;
    procedure LaunchAsynchCallback(a: integer);
    procedure RemoveCallback;
  end;

  TBidirServer = class(TInterfacedObject, IBidirService)
  protected
    fCallback: IBidirCallback;
    // IBidirService implementation methods
    function TestRest(a, b: integer; out c: RawUTF8): variant;
    function TestRestCustom(a: integer): TServiceCustomAnswer;
    function TestCallback(d: Integer; const callback: IBidirCallback): boolean;
    procedure LaunchAsynchCallback(a: integer);
    procedure RemoveCallback;
  public
    function LaunchSynchCallback: integer;
  end;

  /// a test case for all bidirectional remote access, e.g. WebSockets
  TTestBidirectionalRemoteConnection = class(TSynTestCase)
  protected
    fHttpServer: TRestHttpServer;
    fServer: TRestServerFullMemory;
    fBidirServer: TBidirServer;
    fPublicRelayClientsPort, fPublicRelayPort: RawUTF8;
    fPublicRelay: TPublicRelay;
    fPrivateRelay: TPrivateRelay;
    procedure CleanUp; override;
    function NewClient(const port: RawUTF8): TRestHttpClientWebsockets;
    procedure WebsocketsLowLevel(protocol: TWebSocketProtocol;
      opcode: TWebSocketFrameOpCode);
    procedure TestRest(Rest: TRest);
    procedure TestCallback(Rest: TRest);
    procedure SOACallbackViaWebsockets(Ajax, Relay: boolean);
  published
    /// low-level test of our 'synopsejson' WebSockets JSON protocol
    procedure WebsocketsJSONProtocol;
    /// low-level test of our 'synopsebinary' WebSockets binary protocol
    procedure WebsocketsBinaryProtocol;
    procedure WebsocketsBinaryProtocolEncrypted;
    procedure WebsocketsBinaryProtocolCompressed;
    procedure WebsocketsBinaryProtocolCompressEncrypted;
    /// launch the WebSockets-ready HTTP server
    procedure RunHttpServer;
    /// test the callback mechanism via interface-based services on server side
    procedure SOACallbackOnServerSide;
    /// test callbacks via interface-based services over JSON WebSockets
    procedure SOACallbackViaJSONWebsockets;
    /// test callbacks via interface-based services over binary WebSockets
    procedure SOACallbackViaBinaryWebsockets;
    /// initialize SynProtoRelay tunnelling
    procedure RelayStart;
    /// test SynProtoRelay tunnelling over JSON WebSockets
    procedure RelaySOACallbackViaJSONWebsockets;
    /// verify ability to reconect from Private Relay to Public Relay
    procedure RelayConnectionRecreate;
    /// test SynProtoRelay tunnelling over binary WebSockets
    procedure RelaySOACallbackViaBinaryWebsockets;
    /// finalize SynProtoRelay tunnelling
    procedure RelayShutdown;
    /// test Master/Slave replication using TRecordVersion field over WebSockets
    procedure _TRecordVersion;
  end;


  /// this class defined two published methods of type TRestServerCallBack in
  //  order to test the Server-Side ModelRoot/TableName/ID/MethodName RESTful model
  TRestServerTest = class(TRestServerDB)
  published
    /// test ModelRoot/People/ID/DataAsHex
    // - this method is called by TRestServer.URI when a
    // ModelRoot/People/ID/DataAsHex GET request is provided
    // - Parameters values are not used here: this service only need aRecord.ID
    // - SentData is set with incoming data from a PUT method
    // - if called from ModelRoot/People/ID/DataAsHex with GET or PUT methods,
    // TRestServer.URI will create a TOrm instance and set its ID
    // (but won't retrieve its other field values automaticaly)
    // - if called from ModelRoot/People/DataAsHex with GET or PUT methods,
    // TRestServer.URI will leave aRecord.ID=0 before launching it
    // - if called from ModelRoot/DataAsHex with GET or PUT methods,
    // TRestServer.URI will leave aRecord=nil before launching it
    // - implementation must return the HTTP error code (e.g. 200 as success)
    // - Table is overloaded as TOrmPeople here, and still match the
    // TRestServerCallBack prototype: but you have to check the class
    // at runtime: it can be called by another similar but invalid URL, like
    // ModelRoot/OtherTableName/ID/DataAsHex
    procedure DataAsHex(Ctxt: TRestServerURIContext);
    /// method used to test the Server-Side ModelRoot/Sum or
    // ModelRoot/People/Sum Requests with JSON process
    // - implementation of this method returns the sum of two floating-points,
    // named A and B, as in the public TOrmPeople.Sum() method,
    // which implements the Client-Side of this service
    // - Table nor ID are never used here
    procedure Sum(Ctxt: TRestServerURIContext);
    /// method used to test the Server-Side ModelRoot/Sum or
    // ModelRoot/People/Sum Requests with variant process
    procedure Sum2(Ctxt: TRestServerURIContext);
  end;




implementation


{ TTestSQLite3Engine }

function TTestSQLite3Engine.OnBackupProgress(Sender: TSQLDatabaseBackupThread): boolean;
begin
  BackupProgressStep := Sender.Step;
  result := true;
end;

procedure InternalSQLFunctionCharIndex(Context: TSQLite3FunctionContext;
  argc: integer; var argv: TSQLite3ValueArray); cdecl;
var
  StartPos: integer;
begin
  case argc of
    2:
      StartPos := 1;
    3:
      begin
        StartPos := sqlite3.value_int64(argv[2]);
        if StartPos <= 0 then
          StartPos := 1;
      end;
  else
    begin
      ErrorWrongNumberOfArgs(Context);
      exit;
    end;
  end;
  if (sqlite3.value_type(argv[0]) = SQLITE_NULL) or
     (sqlite3.value_type(argv[1]) = SQLITE_NULL) then
    sqlite3.result_int64(Context, 0)
  else
    sqlite3.result_int64(Context, PosEx(sqlite3.value_text(argv[0]),
      sqlite3.value_text(argv[1]), StartPos));
end;

const
  // BLOBs are stored as array of byte to avoid any charset conflict
  BlobDali: array[0..3] of byte = (
    97, 233, 224, 231);
  BlobMonet: array[0..13] of byte = (
    224, 233, 231, ord('d'), ord('s'), ord('j'), ord('d'), ord('s'),
    ord('B'), ord('L'), ord('O'), ord('B'), ord('2'), ord('3'));

  UTF8_E0_F4_BYTES: array[0..5] of byte = (
    $E0, $E7, $E8, $E9, $EA, $F4);

var
  _uE0, _uE7, _uE8, _uE9, _uEA, _uF4: RawUTF8;

procedure TTestSQLite3Engine.DatabaseDirectAccess;

  procedure InsertData(n: integer);
  var
    i: integer;
    s, ins: RawUTF8;
    R: TSQLRequest;
  begin
    // this is a lot faster than sqlite3 itself, even if it use Utf-8 encoding:
    // -> we test the engine speed, not the test routines speed :)
    ins :=
      'INSERT INTO People (FirstName,LastName,Data,YearOfBirth,YearOfDeath) VALUES (''';
    for i := 1 to n do
    begin
      UInt32ToUtf8(i, s);
     // we put some accents in order to test UTF-8 encoding
      R.Prepare(Demo.DB, ins + 'Salvador' + s + ''', ''Dali'', ?, 1904, 1989);');
      R.Bind(1, @BlobDali, 4); // Bind Blob
      R.Execute;
      Demo.Execute(ins + 'Samuel Finley Breese' + s + ''', ''Morse'', ''a' +
        _uE9 + _uE0 + _uE7 + ''', 1791, 1872);');
      Demo.Execute(ins + 'Sergei' + s + ''', ''Rachmaninoff'', ''' + _uE9 + 'z' +
        _uE7 + 'b'', 1873, 1943);');
      Demo.Execute(ins + 'Alexandre' + s + ''', ''Dumas'', ''' + _uE9 + _uE7 +
        'b'', 1802, 1870);');
      Demo.Execute(ins + 'Franz' + s + ''', ''Schubert'', ''' + _uE9 + _uE0 +
        _uE7 + 'a'', 1797, 1828);');
      Demo.Execute(ins + 'Leonardo' + s + ''', ''da Vin' + _uE7 + 'i'', ''@' +
        _uE7 + 'b'', 1452, 1519);');
      Demo.Execute(ins + 'Aldous Leonard' + s + ''', ''Huxley'', ''' + _uE9 +
        _uE0 + ''', 1894, 1963);');
      R.Prepare(Demo.DB, ins + 'Claud' + _uE8 + s + #10#7''', ''M' + _uF4 +
        'net'', ?, 1840, 1926);');
      R.Bind(1, @BlobMonet, sizeof(BlobMonet)); // Bind Blob
      R.Execute;
      R.Prepare(Demo.DB,
        'INSERT INTO People (FirstName,LastName,Data,YearOfBirth,YearOfDeath)' +
        ' VALUES (?,?,?,?,?)');
      R.BindS(1, string('Albert' + s));
      R.BindS(2, 'Einstein');
      R.Bind(3, _uE9 + _uE7 + 'p');
      R.Bind(4, 1879);
      R.Bind(5, 1955);
      R.Execute;
      // Demo.Execute(ins+'Albert'+s+''', ''Einstein'', '''+_uE9+_uE7+'p'', 1879, 1955);');
      Demo.Execute(ins + 'Johannes' + s + ''', ''Gutenberg'', ''' + _uEA +
        'mls'', 1400, 1468);');
      Demo.Execute(ins + 'Jane' + s + ''', ''Aust' + _uE8 + 'n'', ''' + _uE7 +
        _uE0 + _uE7 + 'm'', 1775, 1817);');
    end;
  end;

var
  SoundexValues: array[0..5] of RawUTF8;
  Names: TRawUTF8DynArray;
  i, i1, i2: integer;
  Res: Int64;
  id: TID;
  password, s: RawUTF8;
  R: TSQLRequest;
begin
  check(JSONGetID('{"id":123}', id) and
        (id = 123));
  check(JSONGetID('{"rowid":1234}', id) and
        (id = 1234));
  check(JSONGetID(' { "id": 123}', id) and
        (id = 123));
  check(JSONGetID(' { "ROWID": 1234}', id) and
        (id = 1234));
  check(JSONGetID('{id:123}', id) and
        (id = 123));
  check(JSONGetID('{rowid:1234}', id) and
        (id = 1234));
  check(not JSONGetID('{"id":0}', id));
  check(not JSONGetID('{"id":-10}', id));
  check(not JSONGetID('{"id":null}', id));
  check(not JSONGetID('{"ROWID":null}', id));
  check(not JSONGetID('{id:0}', id));
  check(not JSONGetID('{id:-10}', id));
  check(not JSONGetID('{"ide":123}', id));
  check(not JSONGetID('{"rowide":1234}', id));
  check(not JSONGetID('{"as":123}', id));
  check(not JSONGetID('{"s":1234}', id));
  check(not JSONGetID('"ide":123}', id));
  check(not JSONGetID('{ "rowide":1234}', id));
  if ClassType = TTestMemoryBased then
    TempFileName := SQLITE_MEMORY_DATABASE_NAME
  else
  begin
    TempFileName := 'test.db3';
    DeleteFile(TempFileName); // use a temporary file
    {$ifndef NOSQLITE3ENCRYPT}
    if ClassType <> TTestFileBasedMemoryMap then
      // memory map is not compatible with our encryption
      password := 'password1';
    {$endif NOSQLITE3ENCRYPT}
  end;
  EncryptedFile := (password <> '');
  Demo := TSQLDataBase.Create(TempFileName, password);
  Demo.Synchronous := smOff;
  Demo.LockingMode := lmExclusive;
  if ClassType = TTestFileBasedMemoryMap then
    Demo.MemoryMappedMB := 256; // will do nothing for SQLite3 < 3.7.17
  R.Prepare(Demo.DB, 'select mod(?,?)');
  for i1 := 0 to 100 do
    for i2 := 1 to 100 do
    begin
      R.Bind(1, i1);
      R.Bind(2, i2);
      check(R.Step = SQLITE_ROW);
      check(R.FieldInt(0) = i1 mod i2);
      R.Reset;
    end;
  R.Close;
  SoundexValues[0] := 'bonjour';
  SoundexValues[1] := 'bonchour';
  SoundexValues[2] := 'Bnjr';
  SoundexValues[3] := 'mohammad';
  SoundexValues[4] := 'mohhhammeeet';
  SoundexValues[5] := 'bonjourtr' + _uE8 + 'slongmotquid' + _uE9 + 'passe';
  for i1 := 0 to high(SoundexValues) do
  begin
    s := FormatUTF8('SELECT SoundEx("%");', [SoundexValues[i1]]);
    Demo.Execute(s, Res);
    CheckUTF8(Res = SoundExUTF8(pointer(SoundexValues[i1])), s);
  end;
  for i1 := 0 to high(SoundexValues) do
  begin
    s := FormatUTF8('SELECT SoundExFr("%");', [SoundexValues[i1]]);
    Demo.Execute(s, Res);
    CheckUTF8(Res = SoundExUTF8(pointer(SoundexValues[i1]), nil, sndxFrench), s);
  end;
  for i1 := 0 to high(SoundexValues) do
  begin
    s := FormatUTF8('SELECT SoundExEs("%");', [SoundexValues[i1]]);
    Demo.Execute(s, Res);
    CheckUTF8(Res = SoundExUTF8(pointer(SoundexValues[i1]), nil, sndxSpanish), s);
  end;
  Demo.RegisterSQLFunction(InternalSQLFunctionCharIndex, 2, 'CharIndex');
  Demo.RegisterSQLFunction(InternalSQLFunctionCharIndex, 3, 'CharIndex');
  for i1 := 0 to high(SoundexValues) do
  begin
    s := FormatUTF8('SELECT CharIndex("o","%");', [SoundexValues[i1]]);
    Demo.Execute(s, Res);
    CheckUTF8(Res = PosEx('o', SoundexValues[i1]), s);
    s := FormatUTF8('SELECT CharIndex("o","%",5);', [SoundexValues[i1]]);
    Demo.Execute(s, Res);
    CheckUTF8(Res = PosEx('o', SoundexValues[i1], 5), s);
  end;
  Demo.UseCache := true; // use the cache for the JSON requests
  Demo.WALMode := InheritsFrom(TTestFileBasedWAL); // test Write-Ahead Logging
  check(Demo.WALMode = InheritsFrom(TTestFileBasedWAL));
  Demo.Execute(' CREATE TABLE IF NOT EXISTS People (' +
    ' ID INTEGER PRIMARY KEY,' + ' FirstName TEXT COLLATE SYSTEMNOCASE,' +
    ' LastName TEXT,' + ' Data BLOB,' + ' YearOfBirth INTEGER,' +
    ' YearOfDeath INTEGER); ');
  // Inserting data 1x without transaction ');
  InsertData(1);
  { Insert some sample data - now with transaction. Multiple records are
    inserted and not yet commited until the transaction is finally ended.
    This single transaction is very fast compared to multiple individual
    transactions. It is even faster than other database engines. }
  Demo.TransactionBegin;
  InsertData(1000);
  Demo.Commit;
  Req := 'SELECT * FROM People WHERE LastName=''M' + _uF4 + 'net'' ORDER BY FirstName;';
  check(WinAnsiToUtf8(Utf8ToWinAnsi(Req)) = Req, 'WinAnsiToUtf8/Utf8ToWinAnsi');
  JS := Demo.ExecuteJSON(Req); // get result in JSON format
  FileFromString(JS, 'Test1.json');
  check(Hash32(JS) = $40C1649A, 'Expected ExecuteJSON result not retrieved');
  {$ifndef NOSQLITE3ENCRYPT}
  if password <> '' then
  begin // check file encryption password change
    check(Demo.MemoryMappedMB = 0, 'mmap pragma disallowed');
    FreeAndNil(Demo); // if any exception occurs in Create(), Demo.Free is OK
    check(IsSQLite3File(TempFileName));
    check(IsSQLite3FileEncrypted(TempFileName));
    check(not IsOldSQLEncryptTable(TempFileName));
    check(not ChangeSQLEncryptTablePassWord(TempFileName, 'password1', 'password1'));
    check(IsSQLite3File(TempFileName));
    check(IsSQLite3FileEncrypted(TempFileName));
    check(not IsOldSQLEncryptTable(TempFileName));
    check(ChangeSQLEncryptTablePassWord(TempFileName, 'password1', ''));
    check(IsSQLite3File(TempFileName));
    check(not IsOldSQLEncryptTable(TempFileName));
    check(not IsSQLite3FileEncrypted(TempFileName));
    check(ChangeSQLEncryptTablePassWord(TempFileName, '', 'NewPass'));
    check(IsSQLite3File(TempFileName));
    check(IsSQLite3FileEncrypted(TempFileName));
    check(not IsOldSQLEncryptTable(TempFileName));
    Demo := TSQLDataBase.Create(TempFileName, 'NewPass'); // reuse the temporary file
    Demo.Synchronous := smOff;
    Demo.LockingMode := lmExclusive;
    Demo.UseCache := true; // use the cache for the JSON requests
    Demo.WALMode := InheritsFrom(TTestFileBasedWAL); // test Write-Ahead Logging
    check(Demo.WALMode = InheritsFrom(TTestFileBasedWAL));
    check(Demo.MemoryMappedMB = 0, 'mmap pragma disallowed');
    check(Hash32(Demo.ExecuteJSON(Req)) = $40C1649A, 'ExecuteJSON crypted');
    check(Demo.MemoryMappedMB = 0, 'mmap pragma disallowed');
  end
  else
  {$endif NOSQLITE3ENCRYPT}
  if ClassType = TTestFileBasedMemoryMap then
  begin // force re-open to test reading
    FreeAndNil(Demo);
    Demo := TSQLDataBase.Create(TempFileName, password);
    Demo.Synchronous := smOff;
    Demo.LockingMode := lmExclusive;
    Demo.MemoryMappedMB := 256;
    Demo.UseCache := true;
  end;
  Demo.GetTableNames(Names);
  check(length(Names) = 1);
  check(Names[0] = 'People');
  Demo.Execute(
    'SELECT Concat(FirstName," and ") FROM People WHERE LastName="Einstein"', s);
  check(Hash32(s) = $68A74D8E, 'Albert1 and Albert1 and Albert2 and Albert3 and ...');
  i1 := Demo.Execute(
    'SELECT FirstName from People WHERE FirstName like "%eona%"', Names);
  check(i1 = 2002, 'like/strcspn');
  check(Names[i1] = '');
  for i := 0 to i1 - 1 do
    check(PosEx('eona', Names[i]) > 0);
end;

procedure TTestSQLite3Engine.VirtualTableDirectAccess;
const
  LOG1: RawUTF8 =
    'D:\Dev\lib\SQLite3\exe\TestSQL3.exe 1.2.3.4 (2011-04-07)'#13#10 +
    'Host=MyPC User=MySelf CPU=2*0-15-1027 OS=2.3=5.1.2600 Wow64=0 Freq=3579545'#13#10 +
    'TSynLog 1.13 LVCL 2011-04-07 12:04:09'#13#10#13#10 +
    '20110407 12040904 debug {"TObjectList(00AF8D00)":["TObjectList(00AF8D20)",' +
    '"TObjectList(00AF8D60)","TFileVersion(00ADC0B0)","TSynMapFile(00ACC990)"]}';
var
  Res: Int64;
  s, s2, s3: RawUTF8;
  n: PtrInt;
begin
  // register the Log virtual table module to this connection
  RegisterVirtualTableModule(TOrmVirtualTableLog, Demo);
  // test Log virtual table module
  FileFromString(LOG1, 'temptest.log');
  Demo.Execute('CREATE VIRTUAL TABLE test USING log(temptest.log);');
  Demo.Execute('select count(*) from test', Res);
  check(Res = 1);
  n := 0;
  s := Demo.ExecuteJSON('select * from test', False, @n);
  check(s <> '');
  check(n = Res);
  s2 := Demo.ExecuteJSON('select * from test where rowid=2', False, @n);
  check(s2 = '{"fieldCount":3,"values":["DateTime","Level","Content"],"rowCount":0}'#$A);
  check(n = 0);
  s2 := Demo.ExecuteJSON('select * from test where rowid=1', False, @n);
  check(s2 <> '');
  check(s = s2);
  check(n = 1);
  n := 0;
  s3 := Demo.ExecuteJSON('select * from test where level=2', False, @n);
  check(n = 1);
  check(s3 =
    '{"fieldCount":3,"values":["DateTime","Level","Content","2011-04-07T12:04:09.064",' +
    '2,"20110407 12040904 debug {\"TObjectList(00AF8D00)\":[\"TObjectList(00AF8D20)\",' +
    '\"TObjectList(00AF8D60)\",\"TFileVersion(00ADC0B0)\",\"TSynMapFile(00ACC990)\"]}"],' +
    '"rowCount":1}'#$A);
  s3 := Demo.ExecuteJSON('select * from test where level=3', False, @n);
  CheckEqual(s3,
    '{"fieldCount":3,"values":["DateTime","Level","Content"],"rowCount":0}'#$A);
  CheckEqual(n, 0);
end;

{$ifdef TEST_REGEXP}
procedure TTestSQLite3Engine.RegexpFunction;
const
  EXPRESSIONS: array[0..2] of RawUTF8 = (
    '\bFinley\b', '^Samuel F', '\bFinley\b');
var
  Model: TOrmModel;
  Client: TRestClientDB;
  i, n: integer;
begin
  Model := TOrmModel.Create([TOrmPeople]);
  Client := TRestClientDB.Create(Model, nil, 'test.db3', TRestServerDB, false, '');
  try
    if CheckFailed(CreateRegExpFunction(Client.Server.DB.DB)) then
      exit;
    for i := 0 to high(EXPRESSIONS) do
      with TOrmPeople.CreateAndFillPrepare(Client.Orm,
        'FirstName REGEXP ?', [EXPRESSIONS[i]]) do
      try
        if not CheckFailed(fFill <> nil) then
        begin
          check(fFill.Table.RowCount = 1001);
          n := 0;
          while FillOne do
          begin
            check(LastName = 'Morse');
            check(IdemPChar(pointer(FirstName), 'SAMUEL FINLEY '));
            inc(n);
          end;
          check(n = 1001);
        end;
        Client.Server.DB.CacheFlush; // force compile '\bFinley\b' twice
      finally
        Free;
      end;
  finally
    Client.Free;
    Model.Free;
  end;
end;
{$endif TEST_REGEXP}

type
  TOrmPeopleVersioned = class(TOrmPeople)
  protected
    fVersion: TRecordVersion;
  published
    property Version: TRecordVersion
      read fVersion write fVersion;
  end;

procedure TestMasterSlaveRecordVersion(Test: TSynTestCase; const DBExt: TFileName);

  procedure TestMasterSlave(Master, Slave: TRestServer; SynchronizeFromMaster: TRest);
  var
    res: TRecordVersion;
    Rec1, Rec2: TOrmPeopleVersioned;
  begin
    if SynchronizeFromMaster <> nil then
      res := Slave.Server.RecordVersionSynchronizeSlave(
        TOrmPeopleVersioned, SynchronizeFromMaster.Orm, 500)
    else
      res := Slave.Server.RecordVersionCurrent;
    Test.CheckEqual(res, Master.Server.RecordVersionCurrent);
    Rec1 := TOrmPeopleVersioned.CreateAndFillPrepare(
      Master.Orm, 'order by ID', '*');
    Rec2 := TOrmPeopleVersioned.CreateAndFillPrepare(
      Slave.Orm, 'order by ID', '*');
    try
      Test.CheckEqual(Rec1.FillTable.RowCount, Rec2.FillTable.RowCount);
      while Rec1.FillOne do
      begin
        Test.check(Rec2.FillOne);
        Test.check(Rec1.SameRecord(Rec2), 'simple fields');
        Test.CheckEqual(Rec1.Version, Rec2.Version);
      end;
    finally
      Rec1.Free;
      Rec2.Free;
    end;
  end;

var
  Model: TOrmModel;
  Master, Slave1, Slave2: TRestServerDB;
  MasterAccess: TRestClientURI;
  IDs: TIDDynArray;
  Rec: TOrmPeopleVersioned;
  Slave2Callback: IServiceRecordVersionCallback;
  i, n: integer;
  timeout: Int64;

  function CreateServer(const DBFileName: TFileName;
    DeleteDBFile: boolean): TRestServerDB;
  begin
    if DeleteDBFile then
      DeleteFile(DBFileName);
    result := TRestServerDB.Create(TOrmModel.Create(Model), DBFileName, false, '');
    result.Model.Owner := result;
    result.DB.Synchronous := smOff;
    result.DB.LockingMode := lmExclusive;
    result.Server.CreateMissingTables;
  end;

  procedure CreateMaster(DeleteDBFile: boolean);
  var
    serv: TRestHttpServer;
    ws: TRestHttpClientWebsockets;
  begin
    Master := CreateServer('testversion' + DBExt, DeleteDBFile);
    if Test is TTestBidirectionalRemoteConnection then
    begin
      serv := TTestBidirectionalRemoteConnection(Test).fHttpServer;
      Test.check(serv.AddServer(Master));
      serv.WebSocketsEnable(Master, 'key2').Settings.SetFullLog;
      ws := TRestHttpClientWebsockets.Create(
        '127.0.0.1', HTTP_DEFAULTPORT, TOrmModel.Create(Model));
      ws.Model.Owner := ws;
      ws.WebSockets.Settings.SetFullLog;
      Test.check(ws.WebSocketsUpgrade('key2') = '');
      MasterAccess := ws;
    end
    else
      MasterAccess := TRestClientDB.Create(Master);
  end;

begin
  Model := TOrmModel.Create(
    [TOrmPeople, TOrmPeopleVersioned, TOrmTableDeleted], 'root0');
  CreateMaster(true);
  Slave1 := CreateServer('testversionreplicated' + DBExt, true);
  Slave2 := CreateServer('testversioncallback' + DBExt, true);
  try
    Rec := TOrmPeopleVersioned.CreateAndFillPrepare(StringFromFile('Test1.json'));
    try
      // Rec contains 1001 input rows of data
      TestMasterSlave(Master, Slave1, MasterAccess);
      TestMasterSlave(Master, Slave2, MasterAccess);
      n := Rec.FillTable.RowCount;
      Test.check(n > 100);
      for i := 0 to 9 do
      begin
        // first test raw direct add
        Test.check(Rec.FillOne);
        Master.Server.Add(Rec, true, true);
      end;
      TestMasterSlave(Master, Slave1, MasterAccess);
      if Test is TTestBidirectionalRemoteConnection then
      begin
        Test.check(
          TTestBidirectionalRemoteConnection(Test).fHttpServer.RemoveServer(Master));
        TTestBidirectionalRemoteConnection(Test).fHttpServer.RemoveServer(Master);
      end;
      Master.Free; // test TRestServer.InternalRecordVersionMaxFromExisting
      MasterAccess.Free;
      CreateMaster(false);
      MasterAccess.Client.BatchStart(TOrmPeopleVersioned, 10000);
      while Rec.FillOne do
        // fast add via Batch
        Test.check(MasterAccess.Client.BatchAdd(Rec, true, true) >= 0);
      Test.check(MasterAccess.Client.BatchSend(IDs) = HTTP_SUCCESS);
      Test.check(n = length(IDs) + 10);
      Test.check(Rec.FillRewind);
      for i := 0 to 9 do
        Test.check(Rec.FillOne);
      for i := 0 to high(IDs) do
        if Rec.FillOne then
          Test.check(IDs[i] = Rec.IDValue)
        else
          Test.check(false);
      TestMasterSlave(Master, Slave1, MasterAccess);
      TestMasterSlave(Master, Slave2, MasterAccess);
      if Test is TTestBidirectionalRemoteConnection then
      begin
        // asynchronous synchronization via websockets
        Test.check(Master.RecordVersionSynchronizeMasterStart(true));
        Test.check(Slave2.RecordVersionSynchronizeSlaveStart(TOrmPeopleVersioned,
          MasterAccess, nil));
      end
      else
      begin
        // direct synchronization within the same process
        Slave2Callback := TServiceRecordVersionCallback.Create(
          Slave2, MasterAccess, TOrmPeopleVersioned, nil);
        Master.RecordVersionSynchronizeSubscribeMaster(TOrmPeopleVersioned,
          Slave2.Server.RecordVersionCurrent, Slave2Callback);
      end;
      Test.check(Rec.FillRewind);
      for i := 0 to 20 do
      begin
        Test.check(Rec.FillOne);
        Rec.YearOfBirth := Rec.YearOfBirth + 1;
        if i and 3 = 1 then
          Test.check(Master.Server.Delete(TOrmPeopleVersioned, Rec.IDValue))
        else
          Test.check(Master.Server.Update(Rec));
        if i and 3 = 2 then
        begin
          Rec.YearOfBirth := Rec.YearOfBirth + 4;
          Test.check(Master.Server.Update(Rec), 'update twice to increase Version');
        end;
      end;
      TestMasterSlave(Master, Slave1, MasterAccess);
      TestMasterSlave(Master, Slave1, MasterAccess);
      if Test is TTestBidirectionalRemoteConnection then
      begin
        timeout := GetTickCount64 + 3000;
        repeat
          sleep(1)
        until (GetTickCount64 > timeout) or // wait all callbacks to be received
          (Slave2.Server.RecordVersionCurrent = Master.Server.RecordVersionCurrent);
        Test.check(Slave2.RecordVersionSynchronizeSlaveStop(TOrmPeopleVersioned));
      end;
      TestMasterSlave(Master, Slave2, nil);
      TestMasterSlave(Master, Slave2, MasterAccess);
    finally
      Rec.Free;
    end;
    if Test is TTestBidirectionalRemoteConnection then
      TTestBidirectionalRemoteConnection(Test).fHttpServer.RemoveServer(Master);
  finally
    Slave2Callback := nil;
    Slave1.Free; // warning: Free should be in this order for callbacks release
    Slave2.Free;
    Master.Free;
    MasterAccess.Free;
    Model.Free;
  end;
end;

procedure TTestSQLite3Engine._TRecordVersion;
begin
  TestMasterSlaveRecordVersion(self, '.db3');
end;

type
  TOrmPeopleArray = class(TOrmPeople)
  private
    fInts: TIntegerDynArray;
    fCurrency: TCurrencyDynArray;
  {$ifdef PUBLISHRECORD}
    fRec: TFTSMatchInfo;
  {$endif PUBLISHRECORD}
    fFileVersion: TFVs;
    fUTF8: RawUTF8;
  published
  {$ifdef PUBLISHRECORD}
    property Rec: TFTSMatchInfo
      read fRec write fRec;
  {$endif PUBLISHRECORD}
    property U: RawUTF8
      read fUTF8 write fUTF8;
    property Ints: TIntegerDynArray
      index 1 read fInts write fInts;
    property Currency: TCurrencyDynArray
      index 2 read fCurrency write fCurrency;
    property FileVersion: TFVs
      index 3 read fFileVersion write fFileVersion;
  end;

  TOrmPeopleObject = class(TOrmPeople)
  private
    fPersistent: TCollTst;
    fUTF8: TRawUTF8List;
  public
    /// will create internal U/Persistent instances
    constructor Create; override;
    /// will release internal U/Persistent
    destructor Destroy; override;
  published
    property U: TRawUTF8List
      read fUTF8;
    property Persistent: TCollTst
      read fPersistent;
  end;

  TOrmPeopleID = type TID;

  TOrmPeopleToBeDeletedID = type TID;

  TOrmASource = class;

  TOrmADest = class;

  TOrmADests = class(TOrmMany)
  private
    fTime: TDateTime;
    fDest: TOrmADest;
    fSource: TOrmASource;
  published
    property Source: TOrmASource
      read fSource;
    property Dest: TOrmADest
      read fDest;
    property AssociationTime: TDateTime
      read fTime write fTime;
  end;

  TOrmASource = class(TOrmSigned)
  private
    fDestList: TOrmADests;
  published
    property SignatureTime;
    property Signature;
    property DestList: TOrmADests
      read fDestList;
  end;

  TOrmADest = class(TOrmSigned)
  published
    property SignatureTime;
    property Signature;
  end;

  TOrmCustomProps = class(TOrmPeople)
  protected
    fGUID: TGUID;
    fPeopleID: TID;
    fPeople: TOrmPeopleID;
    fPeopleCascade: TOrmPeopleToBeDeletedID;
    {$ifdef PUBLISHRECORD}
    fGUIDXE6: TGUID;
    {$endif}
    class procedure InternalRegisterCustomProperties(Props: TOrmProperties); override;
  public
    property GUID: TGUID
      read fGUID write fGUID;
  published
    property PeopleID: TID
      read fPeopleID write fPeopleID;
    property People: TOrmPeopleID
      read fPeople write fPeople;
    property PeopleCascade: TOrmPeopleToBeDeletedID
      read fPeopleCascade write fPeopleCascade;
    {$ifdef PUBLISHRECORD}
    property GUIDXE6: TGUID
      read fGUIDXE6 write fGUIDXE6;
    {$endif}
  end;

  TOrmFtsTest = class(TOrmFTS3)
  private
    fSubject: RawUTF8;
    fBody: RawUTF8;
  published
    property Subject: RawUTF8
      read fSubject write fSubject;
    property Body: RawUTF8
      read fBody write fBody;
  end;

  TOrmDali1 = class(TOrmVirtualTableAutoID)
  private
    fYearOfBirth: integer;
    fFirstName: RawUTF8;
    fYearOfDeath: word;
  published
    property FirstName: RawUTF8
      read fFirstName write fFirstName;
    property YearOfBirth: integer
      read fYearOfBirth write fYearOfBirth;
    property YearOfDeath: word
      read fYearOfDeath write fYearOfDeath;
  end;

  TOrmDali2 = class(TOrmDali1);


{ TOrmPeopleObject }

constructor TOrmPeopleObject.Create;
begin
  inherited;
  fPersistent := TCollTst.Create;
  fUTF8 := TRawUTF8List.Create;
end;

destructor TOrmPeopleObject.Destroy;
begin
  Persistent.Free;
  U.Free;
  inherited;
end;

class procedure TOrmCustomProps.InternalRegisterCustomProperties(Props: TOrmProperties);
begin
  Props.RegisterCustomPropertyFromTypeName(self, 'TGUID', 'GUID',
    @TOrmCustomProps(nil).fGUID, [aIsUnique], 38);
end;


/// will be re-used by both TTestSQLite3Engine and TTestExternalDatabase
procedure InternalTestMany(Test: TSynTestCase; aClient: TRestOrmClientURI);
var
  MS: TOrmASource;
  MD, MD2: TOrmADest;
  i: integer;
  sID, dID: array[1..100] of Integer;
  res: TIDDynArray;

  procedure CheckOK;
  begin
    if Test.CheckFailed(MS.FillTable <> nil) then
      exit;
    Test.check(MS.FillTable.RowCount >= length(sID));
    while MS.FillOne do
    begin
      Test.check(MS.DestList.Source.fID = MS.fID);
      Test.check(MS.DestList.Dest.SignatureTime <> 0);
      MS.ClearProperties;
      MS.DestList.Source.ClearProperties;
      MS.DestList.Dest.ClearProperties;
    end;
    MS.FillClose;
  end;

begin
  MS := TOrmASource.Create;
  MD := TOrmADest.Create;
  with Test do
  try
    MD.fSignatureTime := TimeLogNow;
    MS.fSignatureTime := MD.fSignatureTime;
    check(MS.DestList <> nil);
    check(MS.DestList.InheritsFrom(TOrmMany));
    check(aClient.TransactionBegin(TOrmASource)); // faster process
    for i := 1 to high(dID) do
    begin
      MD.fSignature := FormatUTF8('% %', [aClient.ClassName, i]);
      dID[i] := aClient.Add(MD, true);
      check(dID[i] > 0);
    end;
    for i := 1 to high(sID) do
    begin
      MS.fSignature := FormatUTF8('% %', [aClient.ClassName, i]);
      sID[i] := aClient.Add(MS, True);
      check(sID[i] > 0);
      MS.DestList.AssociationTime := i;
      check(MS.DestList.ManyAdd(aClient, sID[i], dID[i])); // associate both lists
      check(not MS.DestList.ManyAdd(aClient, sID[i], dID[i], true)); // no dup
    end;
    aClient.Commit;
    for i := 1 to high(dID) do
    begin
      check(MS.DestList.SourceGet(aClient, dID[i], res));
      if not CheckFailed(length(res) = 1) then
        check(res[0] = sID[i]);
      check(MS.DestList.ManySelect(aClient, sID[i], dID[i]));
      check(MS.DestList.AssociationTime = i);
    end;
    for i := 1 to high(sID) do
    begin
      check(MS.DestList.DestGet(aClient, sID[i], res));
      if CheckFailed(length(res) = 1) then
        continue; // avoid GPF
      check(res[0] = dID[i]);
      check(MS.DestList.FillMany(aClient, sID[i]) = 1);
      check(MS.DestList.FillOne);
      check(Integer(MS.DestList.Source) = sID[i]);
      check(Integer(MS.DestList.Dest) = dID[i]);
      check(MS.DestList.AssociationTime = i);
      check(not MS.DestList.FillOne);
      check(MS.DestList.DestGetJoined(aClient, '', sID[i], res));
      if not CheckFailed(length(res) = 1) then
        check(res[0] = dID[i]);
      check(MS.DestList.DestGetJoined(aClient, 'ADest.SignatureTime=:(0):', sID[i], res));
      check(length(res) = 0);
      check(MS.DestList.DestGetJoined(aClient,
        FormatUTF8('ADest.SignatureTime=?', [], [MD.SignatureTime]), sID[i], res));
// 'ADest.SignatureTime=:('+Int64ToUTF8(MD.SignatureTime)+'):',sID[i],res));
      if CheckFailed(length(res) = 1) then
        continue; // avoid GPF
      check(res[0] = dID[i]);
      MD2 := MS.DestList.DestGetJoined(aClient,
        FormatUTF8('ADest.SignatureTime=?', [], [MD.SignatureTime]), sID[i]) as TOrmADest;
// 'ADest.SignatureTime=:('+Int64ToUTF8(MD.SignatureTime)+'):',sID[i]) as TOrmADest;
      if CheckFailed(MD2 <> nil) then
        continue;
      try
        check(MD2.FillOne);
        check(MD2.ID = dID[i]);
        check(MD2.Signature = FormatUTF8('% %', [aClient.ClassName, i]));
      finally
        MD2.Free;
      end;
    end;
    check(MS.FillPrepareMany(aClient, '', [], []));
    CheckOK;
    check(MS.FillPrepareMany(aClient, 'DestList.Dest.SignatureTime<>?', [], [0]));
    CheckOK;
    check(MS.FillPrepareMany(aClient,
      'DestList.Dest.SignatureTime<>% and RowID>=? and DestList.AssociationTime<>0 ' +
      'and SignatureTime=DestList.Dest.SignatureTime ' +
      'and DestList.Dest.Signature<>"DestList.AssociationTime"', [0], [sID[1]]));
    if CheckFailed(MS.FillTable <> nil) then
      exit;
    check(MS.FillTable.RowCount = length(sID));
    for i := 1 to high(sID) do
    begin
      MS.SignatureTime := 0;
      MS.DestList.Dest.SignatureTime := 0;
      if CheckFailed(MS.FillOne) then
        break;
      check(MS.fID = sID[i]);
      check(MS.SignatureTime = MD.fSignatureTime);
      check(MS.DestList.AssociationTime = i);
      check(MS.DestList.Dest.fID = dID[i]);
      check(MS.DestList.Dest.SignatureTime = MD.fSignatureTime);
      check(MS.DestList.Dest.Signature = FormatUTF8('% %', [aClient.ClassName, i]));
    end;
    MS.FillClose;
    check(aClient.TransactionBegin(TOrmADests)); // faster process
    for i := 1 to high(sID) shr 2 do
      check(MS.DestList.ManyDelete(aClient, sID[i * 4], dID[i * 4]));
    aClient.Commit;
    for i := 1 to high(sID) do
      if i and 3 <> 0 then
      begin
        check(MS.DestList.ManySelect(aClient, sID[i], dID[i]));
        check(MS.DestList.AssociationTime = i);
      end
      else
        check(not MS.DestList.ManySelect(aClient, sID[i], dID[i]));
  finally
    MD.Free;
    MS.Free;
  end;
end;

procedure TTestSQLite3Engine._TRestClientDB;
var
  V, V2: TOrmPeople;
  VA: TOrmPeopleArray;
  VO: TOrmPeopleObject;
  VP: TOrmCustomProps;
  FV: TFV;
  ModelC: TOrmModel;
  Client: TRestClientDB;
  Server: TRestServer;
  aStatic: TRestStorageInMemory;
  Curr: Currency;
  DaVinci, s: RawUTF8;
  Refreshed: boolean;
  J: TOrmTable;
  i, n, nupd, ndx: integer;
  IntArray: TInt64DynArray;
  Results: TIDDynArray;
  List: TObjectList;
  Data: RawBlob;
  DataS: TCustomMemoryStream;
  a, b: double;
  BackupFN: TFileName;

  procedure checks(Leonard: boolean; Client: TRestClientUri; const msg: string);
  var
    ID: integer;
  begin
    ID := V.ID; // ClearProperties do ID := 0;
    V.ClearProperties; // reset values
    check(Client.Client.Retrieve(ID, V), msg); // internaly call URL()
    if Leonard then
      check(V.FirstName = 'Leonard')
    else
      check(V.FirstName = 'Leonardo1', msg);
    check(V.LastName = DaVinci, msg);
    check(V.YearOfBirth = 1452, msg);
    check(V.YearOfDeath = 1519, msg);
  end;

  procedure TestDynArray(aClient: TRestClientUri);
  var
    i, j, k, l: integer;
    IDs: TInt64DynArray;
  begin
    VA.ClearProperties;
    for i := 1 to n do
    begin
      aClient.Orm.Retrieve(i, VA);
      check(VA.ID = i);
      check(VA.LastName = 'Dali');
      check(length(VA.Ints) = i shr 5);
      check(length(VA.Currency) = i shr 5);
      check(length(VA.FileVersion) = i shr 5);
      if i and 31 = 0 then
      begin
        check(VA.U = '');
        for j := 0 to high(VA.Ints) do
          check(VA.Ints[j] = (j + 1) shl 5);
        for j := 0 to high(VA.Currency) do
          check(PInt64(@VA.Currency[j])^ = (j + 1) * 3200);
        for j := 0 to high(VA.FileVersion) do
          with VA.FileVersion[j] do
          begin
            k := (j + 1) shl 5;
            check(Major = k);
            check(Minor = k + 2000);
            check(Release = k + 3000);
            check(Build = k + 4000);
            check(Main = IntToStr(k));
            check(Detailed = IntToStr(k + 1000));
          end;
      end
      else
      begin
        check(GetInteger(pointer(VA.U)) = i);
        for j := 0 to high(VA.FileVersion) do
          with VA.FileVersion[j] do
          begin
            k := (j + 1) shl 5;
            check(Major = k);
            check(Minor = k + 2000);
            check(Release = k + 3000);
            check(Build = k + 4000);
          end;
      end;
{$ifdef PUBLISHRECORD}
      check(VA.fRec.nPhrase = i);
      check(VA.fRec.nCol = i * 2);
      check(VA.fRec.hits[2].docs_with_hits = i * 3);
{$endif PUBLISHRECORD}
    end;
    for i := 1 to n shr 5 do
    begin
      k := i shl 5;
      aClient.Orm.OneFieldValues(TOrmPeopleArray, 'ID',
        FormatUTF8('IntegerDynArrayContains(Ints,?)', [], [k]), IDs);
      l := n + 1 - 32 * i;
      check(length(IDs) = l);
      for j := 0 to high(IDs) do
        check(IDs[j] = k + j);
      aClient.Orm.OneFieldValues(TOrmPeopleArray, 'ID',
       FormatUTF8('CardinalDynArrayContains(Ints,?)', [], [k]), IDs);
      check(length(IDs) = l);
      for j := 0 to high(IDs) do
        check(IDs[j] = k + j);
      aClient.Orm.OneFieldValues(TOrmPeopleArray, 'ID',
        FormatUTF8('MyIntegerDynArrayContains(Ints,:("%"):)',
          [BinToBase64WithMagic(@k, sizeof(k))]), IDs);
      check(length(IDs) = l);
      for j := 0 to high(IDs) do
        check(IDs[j] = k + j);
    end;
  end;

  procedure TestObject(aClient: TRestClientUri);
  var
    i, j, k: integer;
  begin
    for i := 1 to n do
    begin
      VO.ClearProperties;
      aClient.Orm.Retrieve(i, VO);
      check(VO.ID = i);
      check(VO.LastName = 'Morse');
      check(VO.U.Count = i shr 5);
      for j := 0 to VO.U.Count - 1 do
        check(GetInteger(pointer(VO.U[j])) = (j + 1) shl 5);
      check(VO.Persistent.One.Length = i);
      check(VO.Persistent.One.Color = i + 100);
      check(GetInteger(pointer(VO.Persistent.One.Name)) = i);
      check(VO.Persistent.Coll.Count = i shr 5);
      for j := 0 to VO.Persistent.Coll.Count - 1 do
        with VO.Persistent.Coll[j] do
        begin
          k := (j + 1) shl 5;
          check(Color = k + 1000);
          check(Length = k * 2);
          check(GetInteger(pointer(Name)) = k * 3);
        end;
    end;
  end;

  procedure TestFTS3(aClient: TRestClientUri);
  var
    FTS: TOrmFtsTest;
    StartID, i, c: integer;
    IntResult: TIDDynArray;
    cu: RawUTF8;
  const
    COUNT = 400;
  begin
    if CheckFailed(Length(IntArray) > COUNT * 2) then
      exit;
    FTS := TOrmFtsTest.Create;
    try
      if aClient = Client then
        StartID := 0
      else
        StartID := COUNT;
      check(aClient.Orm.TransactionBegin(TOrmFtsTest)); // MUCH faster with this
      for i := StartID to StartID + COUNT - 1 do
      begin
        FTS.DocID := IntArray[i];
        FTS.Subject := aClient.Orm.OneFieldValue(TOrmPeople, 'FirstName', FTS.DocID);
        check(IdemPChar(pointer(FTS.Subject), 'SALVADOR'));
        FTS.Body := FTS.Subject + ' bodY' + Int32ToUtf8(FTS.DocID);
        aClient.Orm.Add(FTS, true);
      end;
      aClient.Orm.Commit; // Commit must be BEFORE OptimizeFTS3, memory leak otherwise
      check(FTS.OptimizeFTS3Index(Client.Server.Server));
      for i := StartID to StartID + COUNT - 1 do
      begin
        check(IdemPChar(pointer(aClient.Orm.OneFieldValue(TOrmFtsTest, 'Subject',
          IntArray[i])), 'SALVADOR'));
        FTS.DocID := 0;
        FTS.Subject := '';
        FTS.Body := '';
        check(aClient.Orm.Retrieve(IntArray[i], FTS));
        check(FTS.DocID = IntArray[i]);
        check(IdemPChar(pointer(FTS.Subject), 'SALVADOR'));
        check(PosEx(Int32ToUtf8(FTS.DocID), FTS.Body, 1) > 0);
      end;
      check(aClient.Orm.FTSMatch(
        TOrmFtsTest, 'Subject MATCH "salVador1"', IntResult));
      for i := 0 to high(IntResult) do
        check(SameTextU(aClient.Orm.OneFieldValue(TOrmPeople, 'FirstName',
          IntResult[i]), 'SALVADOR1'));
      check(aClient.Orm.FTSMatch(
        TOrmFtsTest, 'Subject MATCH "salVador1*"', IntResult));
      for i := 0 to high(IntResult) do
        check(IdemPChar(pointer(aClient.Orm.OneFieldValue(TOrmPeople,
          'FirstName', IntResult[i])), 'SALVADOR1'));
      check(not aClient.Orm.FTSMatch(
        TOrmFtsTest, 'body*', IntResult, [1]), 'invalid count');
      for c := 1 to 9 do
      begin
        cu := SmallUInt32UTF8[c];
        IntResult := nil;
        check(aClient.Orm.FTSMatch(
          TOrmFtsTest, 'Body MATCH "body' + cu + '*"', IntResult));
        check(length(IntResult) > 0);
        for i := 0 to high(IntResult) do
          check(UInt32ToUtf8(IntResult[i])[1] = AnsiChar(c + 48));
        IntResult := nil;
        check(aClient.Orm.FTSMatch(
          TOrmFtsTest, 'body' + cu + '*', IntResult, [1, 0.5]), 'rank');
        check(length(IntResult) > 0);
        for i := 0 to high(IntResult) do
          check(UInt32ToUtf8(IntResult[i])[1] = AnsiChar(c + 48));
      end;
    finally
      FTS.Free;
    end;
  end;

  procedure TestVirtual(aClient: TRestClientUri; DirectSQL: boolean;
    const Msg: string; aClass: TOrmClass);
  var
    n, i, ndx, added: integer;
    VD, VD2: TOrmDali1;
    Rest: TRestOrm;
    Orm: TRestOrmServer;
    stor: TRestStorageInMemoryExternal;
    fn: TFileName;
  begin
    Client.Server.Server.SetStaticVirtualTableDirect(DirectSQL);
    check(Client.Server.Server.ExecuteFmt('DROP TABLE %', [aClass.SQLTableName]));
    Client.Server.Server.CreateMissingTables;
    VD := aClass.Create as TOrmDali1;
    try
      if aClient.Client.TransactionBegin(aClass) then
      try
        // add some items to the file
        V2.FillPrepare(aClient.Orm, 'LastName=:("Dali"):');
        n := 0;
        while V2.FillOne do
        begin
          VD.FirstName := V2.FirstName;
          VD.YearOfBirth := V2.YearOfBirth;
          VD.YearOfDeath := V2.YearOfDeath;
          inc(n);
          added := aClient.Client.Add(VD, true);
          CheckUTF8(added = n, '% Add %<>%', [Msg, added, n]);
        end;
        // update some items in the file
        check(aClient.Client.TableRowCount(aClass) = 1001, 'check SQL Count(*)');
        for i := 1 to n do
        begin
          VD.ClearProperties;
          check(VD.ID = 0);
          check(VD.FirstName = '');
          check(VD.YearOfBirth = 0);
          check(VD.YearOfDeath = 0);
          check(aClient.Client.Retrieve(i, VD), Msg);
          check(VD.ID = i);
          check(IdemPChar(pointer(VD.FirstName), 'SALVADOR'));
          check(VD.YearOfBirth = 1904);
          check(VD.YearOfDeath = 1989);
          VD.YearOfBirth := VD.YearOfBirth + i;
          VD.YearOfDeath := VD.YearOfDeath + i;
          check(aClient.Orm.Update(VD), Msg);
        end;
        // check SQL requests
        for i := 1 to n do
        begin
          VD.ClearProperties;
          check(VD.ID = 0);
          check(VD.FirstName = '');
          check(VD.YearOfBirth = 0);
          check(VD.YearOfDeath = 0);
          CheckUTF8(aClient.Orm.Retrieve(i, VD), '% Retrieve', [Msg]);
          check(IdemPChar(pointer(VD.FirstName), 'SALVADOR'));
          check(VD.YearOfBirth = 1904 + i);
          check(VD.YearOfDeath = 1989 + i);
        end;
        CheckUTF8(aClient.Orm.TableRowCount(aClass) = 1001, '% RowCount', [Msg]);
        Orm := Client.Server.OrmInstance as TRestOrmServer;
        Rest := Orm.StaticVirtualTable[aClass];
        check((Rest as TRestStorageInMemoryExternal).Modified);
        aClient.Orm.Commit; // write to file
        // try to read directly from file content
        Rest := Orm.StaticVirtualTable[aClass];
        if CheckFailed(Rest <> nil) then
          exit;
        fn := TRestStorageInMemoryExternal(Rest).FileName;
        if fn <> '' then
        begin
          // no file content if ':memory' DB
          (Rest as TRestStorageInMemoryExternal).UpdateFile;
          // force update (COMMIT not always calls xCommit)
          stor := TRestStorageInMemoryExternal.Create(
            aClass, nil, fn, {bin=}aClass = TOrmDali2);
          try
            check(stor.Count = n);
            for i := 1 to n do
            begin
              ndx := stor.IDToIndex(i);
              if CheckFailed(ndx >= 0) then
                continue;
              VD2 := stor.Items[ndx] as TOrmDali1;
              if CheckFailed(VD2 <> nil) then
                continue;
              check(VD2.ID = i);
              check(IdemPChar(pointer(VD2.FirstName), 'SALVADOR'));
              check(VD2.YearOfBirth = 1904 + i);
              check(VD2.YearOfDeath = 1989 + i);
            end;
          finally
            stor.Free;
          end;
        end;
      except
        aClient.Orm.RollBack; // will run an error - but this code is correct
      end;
    finally
      VD.Free;
    end;
  end;

  function TestTable(T: TOrmTable): boolean;
  var
    aR, aF: integer;
    db: TOrmTable;
  begin
    result := false;
    if T = nil then
      exit;
    db := TOrmTableDB.Create(Demo, [], Req, true);
    try
      if (db.RowCount <> T.RowCount) or
         (db.FieldCount <> T.FieldCount) then
      begin
        check(False);
        exit;
      end;
      for aR := 0 to db.RowCount do // compare all result values
        for aF := 0 to db.FieldCount - 1 do
          if StrComp(pointer(db.Get(aR, aF)), pointer(T.Get(aR, aF))) <> 0 then
          begin
            check(False);
            exit;
          end;
      result := true;
    finally
      db.Free;
      T.Free;
    end;
  end;

  procedure TestClientDist(ClientDist: TRestClientURI);
  var
    i: integer;
    ids: array[0..3] of TID;
    res: TIDDynArray;
  begin
    try
      check(ClientDist.SetUser('User', 'synopse'));
      TestFTS3(ClientDist);
      TestDynArray(ClientDist);
      TestObject(ClientDist);

      InternalTestMany(self, ClientDist.OrmInstance as TRestOrmClientURI);
      TestVirtual(ClientDist, false, 'Remote Virtual Table access via SQLite', TOrmDali1);
      TestVirtual(ClientDist, false, 'Remote Virtual Table access via SQLite', TOrmDali2);
      TestVirtual(ClientDist, true, 'Remote Direct Virtual Table', TOrmDali1);
      TestVirtual(ClientDist, true, 'Remote Direct Virtual Table', TOrmDali2);
      check(TestTable(ClientDist.Client.List([TOrmPeople], '*', s)), 'through URI and JSON');
      for i := 0 to high(IntArray) do
      begin
        check(ClientDist.Orm.RetrieveBlob(TOrmPeople, IntArray[i], 'Data', Data));
        check((length(Data) = 4) and
              (PInteger(pointer(Data))^ = IntArray[i]));
        V2.IDValue := IntArray[i]; // debug use - do NOT set ID in your programs!
        check(V2.DataAsHex(ClientDist) = BinToHex(Data));
        a := Random;
        b := Random;
        CheckSame(TOrmPeople.Sum(Client, a, b, false), a + b);
        CheckSame(TOrmPeople.Sum(Client, a, b, true), a + b);
      end;
      V.FirstName := 'Leonardo1';
      check(ClientDist.Orm.Update(V));
      checks(false, ClientDist, 'check remote UPDATE/POST');
      V.FirstName := 'Leonard';
      check(ClientDist.Orm.Update(V));
      checks(true, ClientDist, 'check remote UPDATE/POST');
      for i := 0 to high(ids) do
      begin
        V2.YearOfBirth := i;
        ids[i] := ClientDist.Orm.Add(V2, true);
      end;
      for i := 0 to high(ids) do
      begin
        check(ClientDist.Orm.Retrieve(ids[i], V2));
        check(V2.YearOfBirth = i);
      end;
      for i := 0 to high(ids) do
      begin
        ClientDist.Client.BatchStart(TOrmPeople);
        ClientDist.Client.BatchDelete(ids[i]);
        check(ClientDist.Client.BatchSend(res) = HTTP_SUCCESS);
        check(length(res) = 1);
        check(res[0] = HTTP_SUCCESS);
      end;
      for i := 0 to high(ids) do
        check(not ClientDist.Client.Retrieve(ids[i], V2));
      V2.ClearProperties;
      for i := 0 to high(ids) do
      begin
        V2.IDValue := ids[i];
        check(ClientDist.Client.Update(V2), 'test locking');
      end;
      for i := 1 to 400 do // speed test: named pipes are OK
        checks(true, ClientDist, 'caching speed test');
    finally
      ClientDist.Free; // always release the caller instance
    end;
  end;

  procedure Direct(const URI: RawUTF8; Hash: cardinal; const head: RawUTF8 = '');
  var
    call: TRestURIParams;
  begin
    FillCharFast(call, sizeof(call), 0);
    call.Method := 'GET';
    call.url := URI;
    call.InHead := head;
    TRestClientAuthenticationDefault.ClientSessionSign(Client, call);
    call.RestAccessRights := @SUPERVISOR_ACCESS_RIGHTS;
    Server.URI(call);
    check(Hash32(call.OutBody) = Hash);
  end;

var
  ClientDist: TRestClientURI;
  json: RawUTF8;
begin
  V := TOrmPeople.Create;
  VA := TOrmPeopleArray.Create;
  VO := TOrmPeopleObject.Create;
  VP := TOrmCustomProps.Create;
  V2 := nil;
  try
    if ClassType <> TTestMemoryBased then
    begin
      DeleteFile('dali1.json');
      DeleteFile('dali2.data');
    end;
    Demo.RegisterSQLFunction(TypeInfo(TIntegerDynArray), @SortDynArrayInteger,
      'MyIntegerDynArrayContains');
    ModelC := TOrmModel.Create([TOrmPeople, TOrmFtsTest, TOrmASource, TOrmADest,
      TOrmADests, TOrmPeopleArray, TOrmPeopleObject, TOrmDali1, TOrmDali2,
      TOrmCustomProps], 'root');
    ModelC.VirtualTableRegister(TOrmDali1, TOrmVirtualTableJSON);
    ModelC.VirtualTableRegister(TOrmDali2, TOrmVirtualTableBinary);
    try
      Client := TRestClientDB.Create(ModelC, nil, Demo, TRestServerTest, true);
      try
        Client.Server.DB.Synchronous := smOff;
        Client.Server.DB.LockingMode := lmExclusive;
        with Client.Server.Model do
          for i := 0 to high(Tables) do
            if not CheckFailed(GetTableIndex(Tables[i]) = i) then
              check(GetTableIndex(Tables[i].SQLTableName) = i);
        // direct client access test
        Client.Server.Server.CreateMissingTables; // NEED Dest,Source,Dests,...
        check(Client.SetUser('User', 'synopse')); // use default user
        DaVinci := 'da Vin' + _uE7 + 'i';
        check(Client.Orm.Retrieve('LastName=''' + DaVinci + '''', V));
        check(V.FirstName = 'Leonardo1');
        check(V.LastName = DaVinci);
        check(V.YearOfBirth = 1452);
        check(V.YearOfDeath = 1519);
        checks(false, Client, 'Retrieve');
        check(V.ID = 6, 'check RETRIEVE/GET');
        check(Client.Orm.Delete(TOrmPeople, V.ID), 'check DELETE');
        check(not Client.Orm.Retrieve(V.ID, V), 'now this record must not be available');
        check(Client.Orm.Add(V, true) > 0, 'check ADD/PUT');
        checks(false, Client, 'check created value is well retrieved');
        checks(false, Client, 'check caching');
        V2 := V.CreateCopy as TOrmPeople;
        check(V2.SameValues(V));
        V2.Free;
        V2 := TOrmPeople.Create(Client.Orm, V.ID);
        check(V2.SameValues(V));
        check(Client.Orm.Retrieve(V.ID, V2, true), 'with LOCK');
        check(V2.SameValues(V));
        V.FirstName := 'Leonard';
        check(Client.Orm.Update(V));
        check(Client.Orm.UnLock(V), 'unlock');
        checks(true, Client, 'check UPDATE/POST');
        if Client.SessionUser = nil then // only if has the right for EngineExecute
          check(Client.Orm.Execute('VACUUM;'), 'check direct Execute()')
        else
          check(Client.Server.Orm.Execute('VACUUM;'));
        check(V2.FirstName = 'Leonardo1');
        check(not V2.SameValues(V), 'V and V2 must differ');
        check(Client.Client.UpdateFromServer([V2], Refreshed));
        check(Refreshed, 'V2 value will be synchronized with V');
        check(V2.SameValues(V));
        check(Client.Client.UpdateFromServer([V2], Refreshed));
        check(not Refreshed);
        Req := StringReplaceAll(Req, '*',
          Client.Model.Props[TOrmPeople].SQL.TableSimpleFields[true, false]);
        s := 'LastName=''M' + _uF4 + 'net'' ORDER BY FirstName';
        J := Client.Client.List([TOrmPeople], '*', s);
        check(Client.Client.UpdateFromServer([J], Refreshed));
        check(not Refreshed);
        check(TestTable(J), 'incorrect TOrmTableJSON');
        check(Client.Orm.OneFieldValues(TOrmPeople, 'ID', 'LastName=:("Dali"):',
          IntArray));
        check(length(IntArray) = 1001);
        for i := 0 to high(IntArray) do
          check(Client.Orm.OneFieldValue(TOrmPeople, 'LastName', IntArray[i]) = 'Dali');
        List := Client.Orm.RetrieveList(TOrmPeople, 'Lastname=?', ['Dali'],
          'ID,LastName');
        if not CheckFailed(List <> nil) then
        begin
          check(List.Count = Length(IntArray));
          for i := 0 to List.Count - 1 do
            with TOrmPeople(List.List[i]) do
            begin
              check(id = IntArray[i]);
              check(LastName = 'Dali');
              check(FirstName = '');
            end;
          List.Free;
        end;
        Client.Server.SessionsSaveToFile('sessions.data');
        Client.Server.SessionsLoadFromFile('sessions.data', false);
        check(Client.Orm.TransactionBegin(TOrmPeople)); // for UpdateBlob() below
        for i := 0 to high(IntArray) do
        begin
          check(Client.Orm.RetrieveBlob(TOrmPeople, IntArray[i], 'Data', Data));
          check(Length(Data) = sizeof(BlobDali));
          check(CompareMem(pointer(Data), @BlobDali, sizeof(BlobDali)));
          check(Client.Orm.RetrieveBlob(TOrmPeople, IntArray[i], 'Data', DataS));
          check((DataS.Size = 4) and
                (PCardinal(DataS.Memory)^ = $E7E0E961));
          DataS.Free;
          check(Client.Orm.UpdateBlob(TOrmPeople, IntArray[i], 'Data', @IntArray[i], 4));
          check(Client.Orm.RetrieveBlob(TOrmPeople, IntArray[i], 'Data', Data));
          check((length(Data) = 4) and
                (PInteger(pointer(Data))^ = IntArray[i]));
          V2.IDValue := IntArray[i]; // debug use - do NOT set ID in your programs!
          check(V2.DataAsHex(Client) = BinToHex(Data));
          a := Random;
          b := Random;
          check(SameValue(TOrmPeople.Sum(Client, a, b, false), a + b, 1E-10));
          check(SameValue(TOrmPeople.Sum(Client, a, b, true), a + b, 1E-10));
        end;
        Client.Orm.Commit;
        check(Client.Orm.TransactionBegin(TOrmPeopleArray));
        V2.FillPrepare(Client.Orm, 'LastName=:("Dali"):');
        n := 0;
        while V2.FillOne do
        begin
          VA.FillFrom(V2); // fast copy some content from TOrmPeople
          inc(n);
          if n and 31 = 0 then
          begin
            VA.U := '';
            VA.DynArray('Ints').Add(n);
            Curr := n * 0.01;
            VA.DynArray(2).Add(Curr);
            FV.Major := n;
            FV.Minor := n + 2000;
            FV.Release := n + 3000;
            FV.Build := n + 4000;
            FV.Main := IntToStr(n);
            FV.Detailed := IntToStr(n + 1000);
            VA.DynArray('FileVersion').Add(FV);
          end
          else
            VA.U := UInt32ToUTF8(n);
          {$ifdef PUBLISHRECORD}
          VA.fRec.nPhrase := n;
          VA.fRec.nCol := n * 2;
          VA.fRec.hits[2].docs_with_hits := n * 3;
          {$endif PUBLISHRECORD}
          check(Client.Orm.Add(VA, true) = n);
        end;
        Client.Orm.Commit;
        if Client.Orm.TransactionBegin(TOrmPeopleObject) then
        try
          V2.FillPrepare(Client.Orm, 'LastName=:("Morse"):');
          n := 0;
          while V2.FillOne do
          begin
            VO.FillFrom(V2); // fast copy some content from TOrmPeople
            inc(n);
            VO.Persistent.One.Color := n + 100;
            VO.Persistent.One.Length := n;
            VO.Persistent.One.Name := Int32ToUtf8(n);
            if n and 31 = 0 then
            begin
              VO.U.Add(VO.Persistent.One.Name);
              with VO.Persistent.Coll.Add do
              begin
                Color := n + 1000;
                Length := n * 2;
                Name := Int32ToUtf8(n * 3);
              end;
            end;
            check(Client.Orm.Add(VO, true) = n);
          end;
          Client.Orm.Commit;
        except
          Client.Orm.RollBack;
        end;
        TestFTS3(Client);
        TestDynArray(Client);
        TestObject(Client);
        InternalTestMany(self, Client.OrmInstance as TRestOrmClientURI);
        // RegisterVirtualTableModule(TSQLVirtualTableJSON) done above
        TestVirtual(Client, false, 'Virtual Table access via SQLite 1', TOrmDali1);
        TestVirtual(Client, false, 'Virtual Table access via SQLite 1', TOrmDali2);
        TestVirtual(Client, true, 'Direct Virtual Table access 1', TOrmDali1);
        TestVirtual(Client, true, 'Direct Virtual Table access 2', TOrmDali2);
        // remote client access test (via LibraryRequest in-process redirection)
        check(not Client.Server.ExportServerGlobalLibraryRequest({disable=}true));
        check(Client.Server.ExportServerGlobalLibraryRequest);
        check(Client.Server.ExportServerGlobalLibraryRequest);
        TestClientDist(TRestClientLibraryRequest.Create(ModelC, LibraryRequest));
        check(Client.Server.ExportServerGlobalLibraryRequest({disable=}true));
        check(not Client.Server.ExportServerGlobalLibraryRequest({disable=}true));
        // check custom properties content
        if Client.Orm.TransactionBegin(TOrmPeopleObject) then
        try
          V2.FillPrepare(Client.Orm, 'LastName=:("Morse"):');
          n := 0;
          while V2.FillOne do
          begin
            VP.FillFrom(V2); // fast copy some content from TOrmPeople
            inc(n);
            VP.fGUID.D1 := n;
            {$ifdef PUBLISHRECORD}
            VP.fGUIDXE6.D1 := n shl 1;
            {$endif}
            check(Client.Orm.Add(VP, true) = n);
          end;
          Client.Orm.Commit;
          VP.FillPrepare(Client.Orm);
          while VP.FillOne do
          begin
            check(VP.LastName = 'Morse');
            check(Integer(VP.GUID.D1) = VP.ID);
            {$ifdef PUBLISHRECORD}
            check(Integer(VP.GUIDXE6.D1) = VP.ID shl 1);
            {$endif}
          end;
        except
          Client.Orm.RollBack;
        end;
        // test backup API
        BackupFN := Format('backupbackground%s.dbsynlz', [ClassName]);
        deleteFile(BackupFN);
        BackupTimer.Start;
        check(Client.DB.BackupBackground(BackupFN, 1024, 0, OnBackupProgress, true));
        // test per-one and batch requests
        if ClassType = TTestMemoryBased then
        begin // time consuming, so do it once
          Server := TRestServerTest.Create(TOrmModel.Create([TOrmPeople]), false);
          try
            Server.Model.Owner := Server; // we just use TOrmPeople here
            Server.NoAJAXJSON := true;
            DeleteFile('People.json');
            DeleteFile('People.data');
            StaticDataCreate(Server.OrmInstance, TOrmPeople, 'People.data', true);
            json := Demo.ExecuteJSON('SELECT * From People');
            aStatic := (Server.OrmInstance as TRestOrmServer).
              StaticDataServer[TOrmPeople] as TRestStorageInMemory;
            check(aStatic <> nil);
            aStatic.LoadFromJSON(json); // test Add() and JSON fast loading
            for i := 0 to aStatic.Count - 1 do
            begin
              check(Client.Orm.Retrieve(aStatic.ID[i], V), 'test statement+bind speed');
              check(V.SameRecord(aStatic.Items[i]), 'static retrieve');
            end;
            // test our 'REST-minimal' SELECT statement SQL engine
            Direct('/root/People?select=%2A&where=id%3D012', $96F68454);
            Direct('/root/People?select=%2A&where=id%3D:(012):', $96F68454);
            Direct('/root/People?select=%2A&where=LastName%3D%22M%C3%B4net%22', $BBDCF3A6);
            Direct('/root/People?select=%2A&where=YearOfBirth%3D1873', $AF4BCA94);
            Direct('/root/People?select=%2A', $17AE45E3);
            Direct('/root/People?select=%2A&where=YearOfBirth%3D1873&startindex=10&results=20',
              $453C7201);
            Server.URIPagingParameters.SendTotalRowsCountFmt := ',"Total":%';
            Direct('/root/People?select=%2A&where=YearOfBirth%3D1873&startindex=10&results=2',
              $79AFDD53);
            Server.NoAJAXJSON := false;
            Direct('/root/People?select=%2A&where=YearOfBirth%3D1873&startindex=10&results=2',
              $69FDAF5D, 'User-Agent: Ajax');
            Server.NoAJAXJSON := true;
            Server.URIPagingParameters.SendTotalRowsCountFmt := '';
            // test Retrieve() and Delete()
            Check(Server.ExportServerGlobalLibraryRequest);
            ClientDist := TRestClientLibraryRequest.Create(ModelC, LibraryRequest);
            try
              SetLength(IntArray, (aStatic.Count - 1) shr 2);
              for i := 0 to high(IntArray) do
              begin
                IntArray[i] := aStatic.ID[i * 4];
                check(ClientDist.Orm.Retrieve(IntArray[i], V));
                check(V.SameRecord(aStatic.Items[i * 4]));
              end;
              check(V.FillPrepare(Client.Orm, IntArray));
              for i := 0 to High(IntArray) do
              begin
                check(V.FillOne);
                check(V.ID = IntArray[i]);
                check(V.SameRecord(aStatic.Items[i * 4]));
              end;
              V.FillClose; // so that BatchUpdate(V) below will set all fields
              if ClientDist.Orm.TransactionBegin(TOrmPeople) then
              try
                for i := 0 to high(IntArray) do
                  check(ClientDist.Orm.Delete(TOrmPeople, IntArray[i]));
                for i := 0 to high(IntArray) do
                  check(not ClientDist.Orm.Retrieve(IntArray[i], V));
                for i := 0 to aStatic.Count - 1 do
                begin
                  check(ClientDist.Orm.Retrieve(aStatic.ID[i], V));
                  V.YearOfBirth := Random(MaxInt) - Random(MaxInt);
                  check(ClientDist.Orm.Update(V));
                  check(ClientDist.Orm.Retrieve(aStatic.ID[i], V));
                  check(V.SameRecord(aStatic.Items[i]));
                end;
                ClientDist.Orm.Commit;
              except
                ClientDist.Orm.RollBack;
              end
              else
                check(False, 'TransactionBegin');
              // test BATCH sequence usage
              if ClientDist.Orm.TransactionBegin(TOrmPeople) then
              try
                check(ClientDist.Client.BatchStart(TOrmPeople, 5000));
                n := 0;
                for i := 0 to aStatic.Count - 1 do
                  if i and 7 = 0 then
                  begin
                    IntArray[n] := aStatic.ID[i];
                    inc(n);
                  end;
                for i := 0 to n - 1 do
                  // note that here a warning does make sense, since Server.DB=nil
                  check(ClientDist.Client.BatchDelete(IntArray[i]) = i);
                nupd := 0;
                for i := 0 to aStatic.Count - 1 do
                  if i and 7 <> 0 then
                  begin // not yet deleted in BATCH mode
                    check(ClientDist.Orm.Retrieve(aStatic.ID[i], V));
                    V.YearOfBirth := 1800 + nupd;
                    check(ClientDist.Client.BatchUpdate(V) = nupd + n);
                    inc(nupd);
                  end;
                V.LastName := 'New';
                for i := 0 to 1000 do
                begin
                  V.FirstName := RandomUTF8(10);
                  V.YearOfBirth := i + 1000;
                  check(ClientDist.Client.BatchAdd(V, true) = n + nupd + i);
                end;
                check(ClientDist.Client.BatchSend(Results) = 200);
                check(Length(Results) = 9260);
                ClientDist.Orm.Commit;
                for i := 0 to n - 1 do
                  check(not ClientDist.Orm.Retrieve(IntArray[i], V), 'BatchDelete');
                for i := 0 to high(Results) do
                  if i < nupd + n then
                    check(Results[i] = 200)
                  else
                  begin
                    check(Results[i] > 0);
                    ndx := aStatic.IDToIndex(Results[i]);
                    check(ndx >= 0);
                    with TOrmPeople(aStatic.Items[ndx]) do
                    begin
                      check(LastName = 'New', 'BatchAdd');
                      check(YearOfBirth = 1000 + i - nupd - n);
                    end;
                  end;
                for i := 0 to aStatic.Count - 1 do
                  with TOrmPeople(aStatic.Items[i]) do
                    if LastName = 'New' then
                      break
                    else
                      check(YearOfBirth = 1800 + i, 'BatchUpdate');
              except
                ClientDist.Orm.RollBack;
              end
              else
                check(False, 'TransactionBegin');
              // test BATCH update from partial FillPrepare
              V.FillPrepare(ClientDist.Orm, 'LastName=?', ['New'], 'ID,YearOfBirth');
              if ClientDist.Orm.TransactionBegin(TOrmPeople) then
              try
                check(ClientDist.Client.BatchStart(TOrmPeople));
                n := 0;
                V.LastName := 'NotTransmitted';
                while V.FillOne do
                begin
                  check(V.LastName = 'NotTransmitted');
                  check(V.YearOfBirth = n + 1000);
                  V.YearOfBirth := n;
                  if n and 3 = 0 then
                    // will update only V.YearOfBirth specifically
                    ClientDist.Client.BatchUpdate(V, 'YearOfBirth')
                  else
                    // will update only V.YearOfBirth as in previous FillPrepare
                    ClientDist.Client.BatchUpdate(V);
                  inc(n);
                end;
                check(n = 1001);
                SetLength(Results, 0);
                check(ClientDist.Client.BatchSend(Results) = 200);
                check(length(Results) = 1001);
                for i := 0 to high(Results) do
                  check(Results[i] = 200);
                ClientDist.Client.Commit;
              except
                ClientDist.Client.RollBack;
              end
              else
                check(False, 'TransactionBegin');
              V.FillPrepare(ClientDist.Orm, 'LastName=?', ['New'], 'YearOfBirth');
              n := 0;
              while V.FillOne do
              begin
                check(V.LastName = 'NotTransmitted');
                check(V.YearOfBirth = n);
                V.YearOfBirth := 1000;
                inc(n);
              end;
              check(n = length(Results));
              V.FillClose;
              V.LastName := 'last';
              V.FirstName := 'first';
              V.IDValue := 4294967297;
              check(ClientDist.Client.Add(V, true, True) = V.ID);
              V.ClearProperties;
              ClientDist.Client.Retrieve(4294967297, V);
              check(V.FirstName = 'first');
              check(V.ID = 4294967297);
            finally
              ClientDist.Free;
            end;
            aStatic.UpdateFile; // force People.data file content write
            aStatic.ReloadFromFile;
            check(aStatic.Retrieve(11, V), 'reload from people.data');
            check(V.FirstName = 'Jane1');
            check(aStatic.Retrieve(4294967297, V));
            check(V.FirstName = 'first');
            aStatic.FileName := 'People.json';
            aStatic.BinaryFile := false;
            aStatic.Modified := true;
            aStatic.UpdateFile; // force People.json file content write
            aStatic.ReloadFromFile;
            check(aStatic.Retrieve(11, V), 'reload from people.json');
            check(V.FirstName = 'Jane1');
            check(aStatic.Retrieve(4294967297, V));
            check(V.FirstName = 'first');
            aStatic.Delete(TOrmPeople, 4294967297);
            aStatic.UpdateFile;
          finally
            Server.Free;
          end;
        end;
        Client.DB.BackupBackgroundWaitUntilFinished;
      finally
        Client.Free;
      end;
    finally
      ModelC.Free;
    end;
  finally
    V.Free;
    V2.Free;
    VA.Free;
    VP.Free;
    VO.Free;
    FreeAndNil(Demo);
  end;
  {$ifndef NOSQLITE3ENCRYPT}
  if EncryptedFile then
  begin
    check(ChangeSQLEncryptTablePassWord(TempFileName, 'NewPass', '')); // uncrypt file
    check(IsSQLite3File(TempFileName));
  end;
  {$endif NOSQLITE3ENCRYPT}
end;

procedure TTestSQLite3Engine._TOrmTableJSON;
var
  J: TOrmTableJSON;
  i1, i2, aR, aF, F1, F2, n: integer;
  Comp, Comp1, Comp2: TUTF8Compare;
  DoTestODS: boolean;
  {$ifdef ISDELPHI2010}
  Peoples: TObjectList<TOrmPeople>;
  {$endif ISDELPHI2010}
  row: variant;
  lContactDataQueueDynArray: TDynArray;
  lContactDataQueueArray: TRawUTF8DynArray;
  lContactDataQueueJSON: TDocVariantData;
  lData, s: RawUTF8;
  lDocData: TDocVariantData;
const
  TEST_DATA = '[' +
    '{"REC_ID":29915,"CHANNEL":117,"PHONE":"5004392222,12345678","RINGS":0,' +
    '"QUEUE_CALL":2,"PRIORITY":25,"TIMESTAMP_CALL":"2017-10-26T04:48:14",' +
    '"RETRIES_CALL":2,"CONNECTION_TYPE":0,"DISCONNECTION_TYPE":0,"STATUS_CALL":9,' +
    '"GC_STATUS_CALL":5404,"START_COMMUNICATION":"","HELLO":0,"EXTENSION":null,' +
    '"NODE":1,"RESULT_CALL":0,"CONNECT_TIME":0,"SKILL":null,"AGENT_POSITION":0,' +
    '"COMM_RESULT_CODE":null,"V01_TM":"Marcie","V02_TM":"Sayton",' +
    '"V03_TM":"msaytonpe@umn.edu"},' +
    '{"REC_ID":29916,"CHANNEL":132,"PHONE":"1763252375","RINGS":0,"QUEUE_CALL":2,' +
    '"PRIORITY":25,"TIMESTAMP_CALL":"2017-10-26T04:48:14","RETRIES_CALL":2,' +
    '"CONNECTION_TYPE":0,"DISCONNECTION_TYPE":0,"STATUS_CALL":9,' +
    '"GC_STATUS_CALL":5404,"START_COMMUNICATION":"","HELLO":0,"EXTENSION":null,' +
    '"NODE":1,"RESULT_CALL":0,"CONNECT_TIME":0,"SKILL":null,"AGENT_POSITION":0,' +
    '"COMM_RESULT_CODE":null,"V01_TM":"Orsola","V02_TM":"Hainge",' +
    '"V03_TM":"ohaingepf@reverbnation.com"},' +
    '{"REC_ID":29917,"CHANNEL":174,"PHONE":"9149556917","RINGS":0,"QUEUE_CALL":2,' +
    '"PRIORITY":25,"TIMESTAMP_CALL":"2017-10-26T04:48:14","RETRIES_CALL":2,' +
    '"CONNECTION_TYPE":0,"DISCONNECTION_TYPE":0,"STATUS_CALL":9,' +
    '"GC_STATUS_CALL":5404,"START_COMMUNICATION":"","HELLO":0,"EXTENSION":null,' +
    '"NODE":1,"RESULT_CALL":0,"CONNECT_TIME":0,"SKILL":null,"AGENT_POSITION":0,' +
    '"COMM_RESULT_CODE":null,"V01_TM":"Storm","V02_TM":"Jenton",' +
    '"V03_TM":"sjentonpg@senate.gov"}]';
begin
  J := TOrmTableJSON.Create('', JS);
  try
    J.SetFieldType('YearOfBirth', oftModTime);
    if JS <> '' then // avoid memory leak
      with TOrmTableDB.Create(Demo, [], Req, {expand=}true) do
      try
        check(RowCount = J.RowCount);
        check(FieldCount = J.FieldCount);
        SetFieldType('YearOfBirth', oftModTime);
        for aR := 0 to RowCount do
          for aF := 0 to FieldCount - 1 do
            if (aR > 0) and
               (aF = 3) then  // aF=3=Blob
              check(GetBlob(aR, aF) = J.GetBlob(aR, aF))
            else
            begin
              CheckUTF8((GetW(aR, aF) = J.GetW(aR, aF)) and
                    (GetA(aR, aF) = J.GetA(aR, aF)) and
                    (length(GetW(aR, aF)) shr 1 = LengthW(aR, aF)),
                'Get() in Row=% Field=%', [aR, aF]);
              if (aR > 0) and
                 (aF > 3) then
              begin
                check(GetDateTime(aR, aF) = J.GetDateTime(aR, aF));
                check(GetAsDateTime(aR, aF) = J.GetAsDateTime(aR, aF));
              end;
            end;
      finally
        Free;
      end;
    Demo.Execute('VACUUM;');
    with TOrmTableDB.Create(Demo, [], Req, true) do // re-test after VACCUM
    try
      check(RowCount = J.RowCount);
      check(FieldCount = J.FieldCount);
      check(FieldIndex('ID') = 0);
      check(FieldIndex('RowID') = 0);
      for aF := 0 to FieldCount - 1 do
        check(FieldIndex(J.Get(0, aF)) = aF);
      for aR := 0 to RowCount do
        for aF := 0 to FieldCount - 1 do // aF=3=Blob
          check((aF = 3) or (StrIComp(Get(aR, aF), J.Get(aR, aF)) = 0));
      n := 0;
      while Step do
      begin
        for aF := 0 to FieldCount - 1 do // aF=3=Blob
          check((aF = 3) or (StrIComp(FieldBuffer(aF), J.Get(StepRow, aF)) = 0));
        inc(n);
      end;
      check(n = J.RowCount);
      n := 0;
      if not CheckFailed(Step(true, @row)) then
        repeat
          check(row.ID = J.GetAsInteger(StepRow, FieldIndex('ID')));
          check(row.FirstName = J.GetU(StepRow, FieldIndex('FirstName')));
          check(row.LastName = J.GetU(StepRow, FieldIndex('LastName')));
          check(row.YearOfBirth = J.GetAsInteger(StepRow, FieldIndex('YearOfBirth')));
          check(row.YearOfDeath = J.GetAsInteger(StepRow, FieldIndex('YearOfDeath')));
          inc(n);
        until not Step(false, @row);
      check(n = J.RowCount);
      with ToObjectList(TOrmPeople) do
      try
        check(Count = J.RowCount);
        for aR := 1 to Count do
          with TOrmPeople(Items[aR - 1]) do
          begin
            check(IDValue = J.GetAsInteger(aR, FieldIndex('ID')));
            check(FirstName = J.GetU(aR, FieldIndex('FirstName')));
            check(LastName = J.GetU(aR, FieldIndex('LastName')));
            check(YearOfBirth = J.GetAsInteger(aR, FieldIndex('YearOfBirth')));
            check(YearOfDeath = J.GetAsInteger(aR, FieldIndex('YearOfDeath')));
          end;
      finally
        Free;
      end;
      {$ifdef ISDELPHI2010}
      Peoples := ToObjectList<TOrmPeople>;
      try
        check(Peoples.Count = J.RowCount);
        for aR := 1 to Peoples.Count do
          with Peoples[aR - 1] do
          begin
            check(id = J.GetAsInteger(aR, FieldIndex('ID')));
            check(FirstName = J.GetU(aR, FieldIndex('FirstName')));
            check(LastName = J.GetU(aR, FieldIndex('LastName')));
            check(YearOfBirth = J.GetAsInteger(aR, FieldIndex('YearOfBirth')));
            check(YearOfDeath = J.GetAsInteger(aR, FieldIndex('YearOfDeath')));
          end;
      finally
        Peoples.Free;
      end;
      {$endif ISDELPHI2010}
    finally
      Free;
    end;
    for aF := 0 to J.FieldCount - 1 do
    begin
      J.SortFields(aF);
      Comp := J.SortCompare(aF);
      if @Comp <> nil then // BLOB field will be ignored
        for aR := 1 to J.RowCount - 1 do // ensure data sorted in increasing order
          check(Comp(pointer(J.Get(aR, aF)), pointer(J.Get(aR + 1, aF))) <= 0,
            'SortCompare');
    end;
    for aF := 0 to J.FieldCount - 1 do
    begin
      J.SortFields(aF, false);
      Comp := J.SortCompare(aF);
      if @Comp <> nil then // BLOB field will be ignored
        for aR := 1 to J.RowCount - 1 do // ensure data sorted in decreasing order
          check(Comp(pointer(J.Get(aR, aF)), pointer(J.Get(aR + 1, aF))) >= 0,
            'SortCompare');
    end;
    for F1 := 0 to J.FieldCount - 1 do
      for F2 := 0 to J.FieldCount - 1 do
        if F1 <> F2 then
        begin
          Comp1 := J.SortCompare(F1);
          Comp2 := J.SortCompare(F2);
          if (@Comp1 = nil) or
             (@Comp2 = nil) then
            continue; // BLOB fields will be ignored
          J.SortFields([F1, F2], [], []);
          for aR := 1 to J.RowCount - 1 do
          begin
            // ensure data sorted in increasing order for both fields
            aF := Comp1(pointer(J.Get(aR, F1)), pointer(J.Get(aR + 1, F1)));
            check(aF <= 0, 'SortCompare');
            if aF = 0 then // 1st field idem -> check sorted by 2nd field
              check(Comp2(pointer(J.Get(aR, F2)), pointer(J.Get(aR + 1, F2))) <= 0);
          end;
        end;
    for F1 := 0 to J.FieldCount - 1 do
      for F2 := 0 to J.FieldCount - 1 do
        if F1 <> F2 then
        begin
          Comp1 := J.SortCompare(F1);
          Comp2 := J.SortCompare(F2);
          if (@Comp1 = nil) or
             (@Comp2 = nil) then
            continue; // BLOB fields will be ignored
          J.SortFields([F1, F2], [false, true], []); // 1st=DESC, 2nd=ASC order
          for aR := 1 to J.RowCount - 1 do
          begin
          // ensure data sorted in expected order for both fields
            aF := Comp1(pointer(J.Get(aR, F1)), pointer(J.Get(aR + 1, F1)));
            check(aF >= 0, 'SortCompare');
            if aF = 0 then // 1st field idem -> check ASC sorted by 2nd field
              check(Comp2(pointer(J.Get(aR, F2)), pointer(J.Get(aR + 1, F2))) <= 0);
          end;
        end;
  finally
    J.Free;
  end;
  DoTestODS := false;
  if DoTestODS then
    with TOrmTableDB.Create(Demo, [TOrmPeople],
      'select id,FirstName,LastName,YearOfBirth,YearOfDeath from people', true) do
    try
      FileFromString(GetODSDocument(false), 'false.ods');
      FileFromString(GetODSDocument(true), 'true.ods');
    finally
      Free;
    end;
  // some tests to avoid regression about bugs reported by users on forum
  J := TOrmTableJSON.Create('', TEST_DATA);
  try
    check(J.fieldCount = 24);
    check(J.rowCount = 3);
    lData := J.GetJSONValues(true);
    check(lData[1] = '[');
    check(JSONArrayCount(@lData[2]) = J.rowCount);
    check(Hash32(lData) = $B1C13092);
    lData := J.GetJSONValues(false);
    check(Hash32(lData) = $6AB30A2);
  finally
    J.Free;
  end;
  lContactDataQueueJSON.InitJSON(TEST_DATA);
  lContactDataQueueDynArray.Init(TypeInfo(TRawUTF8DynArray), lContactDataQueueArray);
  lContactDataQueueJSON.ToRawUTF8DynArray(lContactDataQueueArray);
  lData := lContactDataQueueDynArray.SaveToJSON;
  lDocData.InitJSON(lData, [dvoJSONObjectParseWithinString]);
  check(lDocData.Count = 3);
  check(Hash32(lDocData.ToJSON) = $FCF948A5);
  check(lDocData.Value[0].QUEUE_CALL = 2);
  s := TEST_DATA;
  i1 := PosEx(',"CHANNEL":132', s);
  i2 := PosEx('}', s, i1);
  delete(s, i1, i2 - i1); // truncate the 2nd object
  J := TOrmTableJSON.Create('', s);
  try
    check(J.fieldCount = 24);
    if not checkfailed(J.rowCount = 3) then
      check(J.Get(2, J.FieldCount - 1) = nil);
    check(J.Get(J.rowCount, J.FieldCount - 1) = 'sjentonpg@senate.gov');
  finally
    J.Free;
  end;
end;

procedure TTestMemoryBased._TOrmTableWritable;

  procedure Test(intern: TRawUTF8Interning);
  var
    s1, s2: TOrmTableJSON;
    w: TOrmTableWritable;
    f, r: integer;
  begin
    s1 := TOrmTableJSON.CreateFromTables([TOrmPeople], '', JS);
    s2 := TOrmTableJSON.CreateFromTables([TOrmPeople], '', JS);
    w := TOrmTableWritable.CreateFromTables([TOrmPeople], '', JS);
    try // merge the same data twice, and validate duplicated columns
      w.NewValuesInterning := intern;
      check(w.RowCount = s1.RowCount);
      check(w.FieldCount = s1.FieldCount);
      w.Join(s2, 'rowid', 'ID'); // s2 will be sorted -> keep s1 untouched
      check(w.RowCount = s1.RowCount);
      check(w.FieldCount = s1.FieldCount * 2 - 1);
      for f := 0 to s1.FieldCount - 1 do
      begin
        check(w.FieldIndex(s1.FieldNames[f]) = f);
        if f > 0 then // f=0='ID' is not duplicated
          check(w.FieldIndex(s1.FieldNames[f] + '2') = f + s1.FieldCount - 1);
      end;
      for r := 1 to w.RowCount do
      begin
        for f := 0 to s1.FieldCount - 1 do
        begin
          check(StrComp(s1.Get(r, f), w.Get(r, f)) = 0);
          if f > 0 then
            check(StrComp(s1.Get(r, f), w.Get(r, f + s1.FieldCount - 1)) = 0);
        end;
      end;
      if intern <> nil then
        check(intern.Count = 0);
      for r := 0 to w.RowCount do
        w.Update(r, 1, UInt32ToUTF8(r and 127));
      for r := 1 to w.RowCount do
        check(w.GetAsInteger(r, 1) = r and 127);
      if intern <> nil then
        check(intern.Count = 128);
    finally
      s1.Free;
      s2.Free;
      w.Free;
      intern.Free;
    end;
  end;

begin
  Test(nil);
  Test(TRawUTF8Interning.Create);
end;

type
  TOrmMapBox = class(TOrmRTree)
  protected
    fMinX, fMaxX, fMinY, fMaxY: double;
  published
    property MinX: double
      read fMinX write fMinX;
    property MaxX: double
      read fMaxX write fMaxX;
    property MinY: double
      read fMinY write fMinY;
    property MaxY: double
      read fMaxY write fMaxY;
  end;

  TOrmMapBoxI = class(TOrmRTreeInteger)
  protected
    fMinX, fMaxX, fMinY, fMaxY: integer;
  published
    property MinX: integer
      read fMinX write fMinX;
    property MaxX: integer
      read fMaxX write fMaxX;
    property MinY: integer
      read fMinY write fMinY;
    property MaxY: integer
      read fMaxY write fMaxY;
  end;

  TOrmMapBoxPlain = class(TOrm)
  protected
    fMinX, fMaxX, fMinY, fMaxY: double;
  published
    property MinX: double
      read fMinX write fMinX;
    property MaxX: double
      read fMaxX write fMaxX;
    property MinY: double
      read fMinY write fMinY;
    property MaxY: double
      read fMaxY write fMaxY;
  end;

procedure TTestMemoryBased._RTree;
var
  Model: TOrmModel;
  Client: TRestClientDB;
  Box: TOrmMapBox;
  BoxI: TOrmMapBoxI;
  //BoxPlain: TOrmMapBoxPlain;
  i: integer;
  timer: TPrecisionTimer;

  procedure CheckBox(i: integer);
  begin
    check(Box.fID = i * 2);
    CheckSame(Box.MinX, i * 1.0);
    CheckSame(Box.MaxX, i * 1.0 + 0.5);
    CheckSame(Box.MinY, i * 2.0);
    CheckSame(Box.MaxY, i * 2.0 + 0.5);
  end;

  procedure CheckBoxI(i: integer);
  begin
    check(BoxI.fID = i * 2);
    check(BoxI.MinX = i);
    check(BoxI.MaxX = i + 2);
    check(BoxI.MinY = i * 2);
    check(BoxI.MaxY = i * 2 + 2);
  end;
{procedure CheckBoxPlain(i: integer);
begin
  check(BoxPlain.fID=i*2);
  CheckSame(BoxPlain.MinX,i*1.0);
  CheckSame(BoxPlain.MaxX,i*1.0+0.5);
  CheckSame(BoxPlain.MinY,i*2.0);
  CheckSame(BoxPlain.MaxY,i*2.0+0.5);
end;}

const
  COUNT = 10000;
begin
  Model := TOrmModel.Create([TOrmMapBox, TOrmMapBoxI, TOrmMapBoxPlain]);
  Client := TRestClientDB.Create(Model, nil, SQLITE_MEMORY_DATABASE_NAME,
    TRestServerDB, false, '');
  try
    Client.Server.Server.CreateMissingTables;
    {timer.Start;
    BoxPlain := TOrmMapBoxPlain.Create;
    try
      Client.TransactionBegin(TOrmMapBoxPlain);
      for i := 1 to COUNT do begin
        BoxPlain.fID := i*2; // force ID
        BoxPlain.MinX := i*1.0;
        BoxPlain.MaxX := i*1.0+0.5;
        BoxPlain.MinY := i*2.0;
        BoxPlain.MaxY := i*2.0+0.5;
        check(Client.Add(BoxPlain,true,true)=i*2);
      end;
      Client.Commit;
      writeln('added in ',timer.Stop); timer.Start;
      with Client.Server as TRestServer do begin
        CreateSQLIndex(TOrmMapBoxPlain,'MinX',false);
        CreateSQLIndex(TOrmMapBoxPlain,'MaxX',false);
        CreateSQLIndex(TOrmMapBoxPlain,'MinY',false);
        CreateSQLIndex(TOrmMapBoxPlain,'MaxY',false);
      end;
      writeln('indexes created in ',timer.Stop); timer.Start;
      for i := 1 to COUNT do begin
        check(Client.Retrieve(i*2,BoxPlain));
        CheckBoxPlain(i);
      end;
      writeln('retrieved by id in ',timer.Stop); timer.Start;
      for i := 1 to COUNT do begin
        BoxPlain.FillPrepare(Client,'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
          [i*1.0+0.25,i*1.0+0.25,i*2.0+0.25,i*2.0+0.25]);
        check(BoxPlain.FillOne);
        CheckBoxPlain(i);
        check(not BoxPlain.FillOne);
      end;
      writeln('retrieved by coords in ',timer.Stop); timer.Start;
    finally
      BoxPlain.Free;
    end;
    NotifyTestSpeed('Without RTree',COUNT,0,@timer);}
    timer.Start;
    Box := TOrmMapBox.Create;
    try
      Client.Orm.TransactionBegin(TOrmMapBox);
      for i := 1 to COUNT do
      begin
        Box.fID := i * 2; // force ID
        Box.MinX := i * 1.0;
        Box.MaxX := i * 1.0 + 0.5;
        Box.MinY := i * 2.0;
        Box.MaxY := i * 2.0 + 0.5;
        check(Client.Orm.Add(Box, true, true) = i * 2);
      end;
      Client.Orm.Commit;
      for i := 1 to COUNT do
      begin
        check(Client.Orm.Retrieve(i * 2, Box));
        CheckBox(i);
      end;
      for i := 1 to COUNT do
      begin
        Box.FillPrepare(Client.Orm,
          'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
          [i * 1.0 + 0.25, i * 1.0 + 0.25, i * 2.0 + 0.25, i * 2.0 + 0.25]);
        check(Box.FillOne);
        CheckBox(i);
        check(not Box.FillOne);
      end;
      Box.FillPrepare(Client.Orm,
        'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
        [1.0, 1.0, 2.0, 2.0]);
      check(Box.FillOne);
      CheckBox(1);
      Box.FillPrepare(Client.Orm,
        'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
        [1.5, 1.5, 2.5, 2.5]);
      check(Box.FillOne);
      CheckBox(1);
    finally
      Box.Free;
    end;
    NotifyTestSpeed('With RTree', COUNT, 0, @timer);
    timer.Start;
    BoxI := TOrmMapBoxI.Create;
    try
      Client.Orm.TransactionBegin(TOrmMapBoxI);
      for i := 1 to COUNT do
      begin
        BoxI.fID := i * 2; // force ID
        BoxI.MinX := i;
        BoxI.MaxX := i + 2;
        BoxI.MinY := i * 2;
        BoxI.MaxY := i * 2 + 2;
        check(Client.Orm.Add(BoxI, true, true) = i * 2);
      end;
      Client.Orm.Commit;
      for i := 1 to COUNT do
      begin
        check(Client.Orm.Retrieve(i * 2, BoxI));
        CheckBoxI(i);
      end;
      for i := 1 to COUNT do
      begin
        BoxI.FillPrepare(Client.Orm,
          'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
          [i + 1, i + 1, i * 2 + 1, i * 2 + 1]);
        check(BoxI.FillOne);
        CheckBoxI(i);
        check(not BoxI.FillOne);
      end;
      BoxI.FillPrepare(Client.Orm,
        'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
        [1, 1, 2, 2]);
      check(BoxI.FillOne);
      CheckBoxI(1);
      BoxI.FillPrepare(Client.Orm,
        'MinX<=? and ?<=MaxX and MinY<=? and ?<=MaxY',
        [3, 3, 4, 4]);
      check(BoxI.FillOne);
      CheckBoxI(1);
    finally
      BoxI.Free;
    end;
    NotifyTestSpeed('With RTreeInteger', COUNT, 0, @timer);
  finally
    Client.Free;
    Model.Free;
  end;
end;
{
  Delphi Win32:
   10000 With RTree in 806.64ms i.e. 12396/s, aver. 80us
   10000 With RTreeInteger in 750.94ms i.e. 13316/s, aver. 75us

   10000 Without RTree in 16.82s i.e. 594/s, aver. 1.68ms (no index)
   10000 Without RTree in 22.96s i.e. 435/s, aver. 2.29ms (with indexes created last)
    added in 136.90ms
    indexes created in 25.02ms
    retrieved by id in 119.87ms
    retrieved by coords in 22.71s
   10000 Without RTree in 23.13s i.e. 432/s, aver. 2.31ms (with indexes created first)

  Delphi Win64:
    10000 With RTree in 737ms i.e. 13568/s, aver. 73us
    10000 With RTreeInteger in 621.83ms i.e. 16081/s, aver. 62us
  FPC Win32:
    10000 With RTree in 852.12ms i.e. 11735/s, aver. 85us
    10000 With RTreeInteger in 764.59ms i.e. 13078/s, aver. 76us
  FPC Win64:
    10000 With RTree in 718.39ms i.e. 13919/s, aver. 71us
    10000 With RTreeInteger in 667.80ms i.e. 14974/s, aver. 66us
  FPC Linux64 (within Windows Linux Layer):
    10000 With RTree in 1.08s i.e. 9218/s, aver. 108us
    10000 With RTreeInteger in 1s i.e. 9966/s, aver. 100us
}

const
  SHARD_MAX = 10000;
  SHARD_RANGE = 1000;

function TTestMemoryBased.CreateShardDB(maxshard: Integer): TRestServer;
begin
  result := TRestServerDB.CreateWithOwnModel([TOrmTest], false, 'shardroot');
  check(TRestStorageShardDB.Create(
    TOrmTest, result, SHARD_RANGE, [], '', maxshard) <> nil);
end;

procedure TTestMemoryBased.ShardWrite;
var
  R: TOrmTest;
  i: integer;
  db: TRestServer;
  b: TRestBatch;
begin
  DirectoryDelete(ExeVersion.ProgramFilePath, 'Test0*.dbs', True);
  db := CreateShardDB(100);
  try
    R := TOrmTest.Create;
    try
      for i := 1 to 50 do
      begin
        R.FillWith(i);
        check(db.Orm.AddWithBlobs(R) = i);
        R.CheckWith(self, i);
      end;
      b := TRestBatch.Create(db.Orm, TOrmTest, SHARD_RANGE div 3, [boExtendedJSON]);
      try
        for i := 51 to SHARD_MAX do
        begin
          R.FillWith(i);
          check(b.Add(R, true, false, ALL_FIELDS) = i - 51);
        end;
        check(db.Orm.BatchSend(b) = HTTP_SUCCESS);
      finally
        b.Free;
      end;
    finally
      R.Free;
    end;
  finally
    db.Free;
  end;
end;

procedure TTestMemoryBased.ShardRead;
var
  R: TOrmTest;
  i: integer;
  db: TRestServer;
begin
  db := CreateShardDB(100);
  try
    R := TOrmTest.Create;
    try
      for i := 1 to SHARD_MAX do
      begin
        check(db.Orm.Retrieve(i, R));
        check(db.Orm.RetrieveBlobFields(R));
        R.CheckWith(self, i, 0);
      end;
    finally
      R.Free;
    end;
  finally
    db.Free;
  end;
end;

procedure TTestMemoryBased.ShardReadAfterPurge;
var
  R: TOrmTest;
  i: integer;
  db: TRestServer;
begin
  check(DeleteFile(ExeVersion.ProgramFilePath + 'Test0000.dbs'));
  check(DeleteFile(ExeVersion.ProgramFilePath + 'Test0001.dbs'));
  db := CreateShardDB(100);
  try
    R := TOrmTest.Create;
    try
      for i := 1 to SHARD_RANGE * 2 do
        check(not db.Orm.Retrieve(i, R));
      for i := SHARD_RANGE * 2 + 1 to SHARD_MAX do
      begin
        check(db.Orm.Retrieve(i, R));
        check(db.Orm.RetrieveBlobFields(R));
        R.CheckWith(self, i, 0);
      end;
    finally
      R.Free;
    end;
  finally
    db.Free;
  end;
end;

procedure TTestMemoryBased._MaxShardCount;
var
  R: TOrmTest;
  i, last: integer;
  db: TRestServer;
  b: TRestBatch;
begin
  db := CreateShardDB(5);
  try
    R := TOrmTest.Create;
    try
      last := SHARD_MAX - SHARD_RANGE * 5;
      for i := 1 to last do
        check(not db.Orm.Retrieve(i, R));
      for i := last + 1 to SHARD_MAX do
      begin
        check(db.Orm.Retrieve(i, R));
        check(db.Orm.RetrieveBlobFields(R));
        R.CheckWith(self, i, 0);
      end;
      b := TRestBatch.Create(db.Orm, TOrmTest, SHARD_RANGE div 3, [boExtendedJSON]);
      try
        for i := SHARD_MAX + 1 to SHARD_MAX + 2000 do
        begin
          R.FillWith(i);
          check(b.Add(R, true) = i - (SHARD_MAX + 1));
        end;
        check(db.Orm.BatchSend(b) = HTTP_SUCCESS);
      finally
        b.Free;
      end;
      last := SHARD_MAX + 2000 - SHARD_RANGE * 5;
      for i := 1 to last do
        check(not db.Orm.Retrieve(i, R));
      for i := last + 1 to SHARD_MAX + 2000 do
      begin
        check(db.Orm.Retrieve(i, R));
        R.CheckWith(self, i, 0, false);
      end;
    finally
      R.Free;
    end;
  finally
    db.Free;
  end;
end;



{ TRestServerTest }

procedure TRestServerTest.DataAsHex(Ctxt: TRestServerURIContext);
var
  aData: RawBlob;
begin
  if (self = nil) or
     (Ctxt.Table <> TOrmPeople) or
     (Ctxt.TableID < 0) then
    Ctxt.Error('Need a valid record and its ID')
  else if Orm.RetrieveBlob(TOrmPeople, Ctxt.TableID, 'Data', aData) then
    Ctxt.Results([BinToHex(aData)])
  else
    Ctxt.Error('Impossible to retrieve the Data BLOB field');
end;

procedure TRestServerTest.Sum(Ctxt: TRestServerURIContext);
var
  a, b: double;
begin
  if UrlDecodeNeedParameters(Ctxt.Parameters, 'A,B') then
  begin
    while Ctxt.Parameters <> nil do
    begin
      UrlDecodeDouble(Ctxt.Parameters, 'A=', a);
      UrlDecodeDouble(Ctxt.Parameters, 'B=', b, @Ctxt.Parameters);
    end;
    Ctxt.Results([a + b]);
  end
  else
    Ctxt.Error('Missing Parameter');
end;

procedure TRestServerTest.Sum2(Ctxt: TRestServerURIContext);
begin
  with Ctxt do
    Results([InputDouble['a'] + InputDouble['b']]);
end;


type
  TBidirCallbackInterfacedObject = class(TInterfacedObject, IBidirCallback)
  protected
    fValue: Integer;
  public
    function Value: Integer;
    procedure AsynchEvent(a: integer);
  end;

  TBidirCallback = class(TInterfacedCallback, IBidirCallback)
  protected
    fValue: Integer;
  public
    function Value: Integer;
    procedure AsynchEvent(a: integer);
  end;


{ TBidirServer }

function TBidirServer.TestRest(a, b: integer; out c: RawUTF8): variant;
begin
  c := Int32ToUtf8(a + b);
  result := _ObjFast(['a', a, 'b', b, 'c', c]);
end;

function TBidirServer.TestRestCustom(a: integer): TServiceCustomAnswer;
begin
  result.Header := BINARY_CONTENT_TYPE_HEADER;
  result.Content := Int32ToUtf8(a) + #0#1;
  result.Status := HTTP_SUCCESS;
end;

function TBidirServer.TestCallback(d: Integer;
  const callback: IBidirCallback): boolean;
begin
  fCallback := callback;
  result := d <> 0;
end;

procedure TBidirServer.LaunchAsynchCallback(a: integer);
begin
  if Assigned(fCallback) then
    fCallback.AsynchEvent(a);
end;

function TBidirServer.LaunchSynchCallback: integer;
begin
  if Assigned(fCallback) then
    result := fCallback.Value
  else
    result := 0;
end;

procedure TBidirServer.RemoveCallback;
begin
  fCallback := nil;
end;


{ TBidirCallbackInterfacedObject }

procedure TBidirCallbackInterfacedObject.AsynchEvent(a: integer);
begin
  inc(fValue, a);
end;

function TBidirCallbackInterfacedObject.Value: integer;
begin
  result := fValue;
end;


{ TBidirCallback }

procedure TBidirCallback.AsynchEvent(a: integer);
begin
  inc(fValue, a);
end;

function TBidirCallback.Value: integer;
begin
  result := fValue;
end;


{ TTestBidirectionalRemoteConnection }

const
  WEBSOCKETS_KEY = 'key';

procedure TTestBidirectionalRemoteConnection.WebsocketsJSONProtocol;
begin
  WebsocketsLowLevel(
    TWebSocketProtocolJSON.Create(''), focText);
end;

procedure TTestBidirectionalRemoteConnection.WebsocketsBinaryProtocol;
begin
  WebsocketsLowLevel(
    TWebSocketProtocolBinary.Create('', false, '', false), focBinary);
end;

procedure TTestBidirectionalRemoteConnection.WebsocketsBinaryProtocolEncrypted;
begin
  WebsocketsLowLevel(
    TWebSocketProtocolBinary.Create('', false, 'pass', false), focBinary);
end;

procedure TTestBidirectionalRemoteConnection.WebsocketsBinaryProtocolCompressed;
begin
  WebsocketsLowLevel(
    TWebSocketProtocolBinary.Create('', false, '', true), focBinary);
end;

procedure TTestBidirectionalRemoteConnection.WebsocketsBinaryProtocolCompressEncrypted;
begin
  WebsocketsLowLevel(
    TWebSocketProtocolBinary.Create('', false, 'pass', true), focBinary);
end;


type // to access protected low-level frame methods
  TWebSocketProtocolRestHook = class(TWebSocketProtocolRest);

procedure TTestBidirectionalRemoteConnection.WebsocketsLowLevel(
  protocol: TWebSocketProtocol; opcode: TWebSocketFrameOpCode);

  procedure TestOne(const content, contentType: RawByteString);
  var
    C1, C2: THttpServerRequest;
    P2: TWebSocketProtocol;
    frame: TWebSocketFrame;
    head: RawUTF8;
    noAnswer1, noAnswer2: boolean;
  begin
    C1 := THttpServerRequest.Create(nil, 0, nil);
    C2 := THttpServerRequest.Create(nil, 0, nil);
    P2 := protocol.Clone('');
    try
      C1.Prepare('url', 'POST', 'headers', content, contentType, '', false);
      noAnswer1 := opcode = focBinary;
      noAnswer2 := not noAnswer1;
      TWebSocketProtocolRestHook(protocol).InputToFrame(C1, noAnswer1, frame, head);
      check(frame.opcode = opcode);
      TWebSocketProtocolRestHook(P2).FrameToInput(frame, noAnswer2, C2);
      check(noAnswer1 = noAnswer2);
      check(C2.URL = 'url');
      check(C2.Method = 'POST');
      check(C2.InHeaders = 'headers');
      check(C2.InContentType = contentType);
      check(C2.InContent = content);
      C1.OutContent := content;
      C1.OutContentType := contentType;
      C1.OutCustomHeaders := 'outheaders';
      frame.opcode := focContinuation;
      head := 'answer';
      TWebSocketProtocolRestHook(protocol).OutputToFrame(C1, 200, head, frame);
      check(frame.opcode = opcode);
      check(TWebSocketProtocolRestHook(P2).FrameToOutput(frame, C2) = 200);
      check(C2.OutContent = content);
      check(C2.OutContentType = contentType);
      check(C2.OutCustomHeaders = 'outheaders');
    finally
      P2.Free;
      C2.Free;
      C1.Free;
    end;
  end;

begin
  try
    TestOne('content', TEXT_CONTENT_TYPE);
    TestOne('{"content":1234}', JSON_CONTENT_TYPE);
    TestOne('"content"', JSON_CONTENT_TYPE);
    TestOne('["json",2]', JSON_CONTENT_TYPE);
    TestOne('binary'#0'data', BINARY_CONTENT_TYPE);
  finally
    protocol.Free;
  end;
end;

procedure TTestBidirectionalRemoteConnection.RunHttpServer;
var
  port: integer;
begin
  TInterfaceFactory.RegisterInterfaces([TypeInfo(IBidirService), TypeInfo(IBidirCallback)]);
  // sicClientDriven services expect authentication for sessions
  fServer := TRestServerFullMemory.CreateWithOwnModel([], true);
  fServer.Server.CreateMissingTables;
  fBidirServer := TBidirServer.Create;
  check(fServer.ServiceDefine(fBidirServer, [IBidirService]) <> nil);
  fHttpServer := TRestHttpServer.Create(HTTP_DEFAULTPORT, [], '+', useBidirSocket);
  check(fHttpServer.AddServer(fServer));
  fHttpServer.WebSocketsEnable(fServer, WEBSOCKETS_KEY, true).Settings.SetFullLog;
  //(fHttpServer.HttpServer as TWebSocketServer).HeartbeatDelay := 5000;
  port := UTF8ToInteger(HTTP_DEFAULTPORT);
  fPublicRelayClientsPort := ToUTF8(port + 1);
  fPublicRelayPort := ToUTF8(port + 2);
end;

procedure TTestBidirectionalRemoteConnection.TestRest(Rest: TRest);
var
  I: IBidirService;
  a, b: integer;
  c: RawUTF8;
  v: variant;
  res: TServiceCustomAnswer;
begin
  Rest.Services.Resolve(IBidirService, I);
  if CheckFailed(Assigned(I), 'Rest IBidirService') then
    exit;
  for a := -10 to 10 do
    for b := -10 to 10 do
    begin
      v := I.TestRest(a, b, c);
      check(GetInteger(pointer(c)) = a + b);
      if CheckFailed(DocVariantType.IsOfType(v)) then
        continue;
      check(v.a = a);
      check(v.b = b);
      check(v.c = c);
    end;
  for a := -10 to 10 do
  begin
    res := I.TestRestCustom(a);
    check(res.Status = HTTP_SUCCESS);
    check(GetInteger(pointer(res.Content)) = a);
    check(res.Content[Length(res.Content)] = #1);
  end;
end;

procedure TTestBidirectionalRemoteConnection.TestCallback(Rest: TRest);
var
  I: IBidirService;
  d: integer;
  subscribed: IBidirCallback;

  procedure WaitUntilNotified;
  var
    timeout: Int64;
  begin
    timeout := GetTickCount64 + 5000;
    while (subscribed.value <> 6) and
          (GetTickCount64 < timeout) do
      sleep(1);
    check(subscribed.value = 6);
  end;

begin
  Rest.Services.Resolve(IBidirService, I);
  if CheckFailed(Assigned(I), 'Callback IBidirService') then
    exit;
  subscribed := TBidirCallbackInterfacedObject.Create;
  for d := -5 to 6 do
  begin
    check(I.TestCallback(d, subscribed) = (d <> 0));
    I.LaunchAsynchCallback(d);
  end;
  WaitUntilNotified;
  check(fBidirServer.LaunchSynchCallback = 6);
  Rest.Services.CallBackUnRegister(subscribed); // manual callback release notify
  subscribed := TBidirCallback.Create(Rest, IBidirCallback); // auto notification
  for d := -5 to 6 do
  begin
    check(I.TestCallback(d, subscribed) = (d <> 0));
    I.LaunchAsynchCallback(d);
  end;
  WaitUntilNotified;
  subscribed := TBidirCallback.Create(Rest, IBidirCallback);
  for d := -5 to 6 do
  begin
    check(I.TestCallback(d, subscribed) = (d <> 0));
    I.LaunchAsynchCallback(d);
    I.RemoveCallback;
  end;
  WaitUntilNotified;
  check(fBidirServer.LaunchSynchCallback = 0);
end; // here TBidirCallback.Free will notify Rest.Services.CallBackUnRegister()

procedure TTestBidirectionalRemoteConnection.SOACallbackOnServerSide;
begin
  TestRest(fServer);
  TestCallback(fServer);
  TestRest(fServer);
end;

function TTestBidirectionalRemoteConnection.NewClient(const port: RawUTF8):
  TRestHttpClientWebsockets;
begin
  result := TRestHttpClientWebsockets.Create('127.0.0.1', port, TOrmModel.Create
    (fServer.Model));
  result.Model.Owner := result;
  result.WebSockets.Settings.SetFullLog;
end;

procedure TTestBidirectionalRemoteConnection.SOACallbackViaWebsockets(
  Ajax, Relay: boolean);

  procedure ServiceDefine(c: TRestHttpClientWebsockets; const msg: string);
  begin
    check(c.SetUser('User', 'synopse'), 'setuser' + msg);
    check(c.ServiceDefine(IBidirService, sicShared) <> nil, 'IBidirService' + msg);
  end;

var
  c1, c2: TRestHttpClientWebsockets;
  port: RawUTF8;
  stats: RawUTF8;
begin
  if Relay then
    port := fPublicRelayClientsPort
  else
    port := HTTP_DEFAULTPORT;
  c1 := NewClient(port);
  try
    // check plain HTTP REST calls
    check(c1.ServerTimestampSynchronize);
    ServiceDefine(c1, '1');
    TestRest(c1);
    // check WebSockets communication
    CheckEqual(c1.WebSocketsUpgrade(WEBSOCKETS_KEY, Ajax, true), '',
      'WebSocketsUpgrade1');
    TestCallback(c1);
    c2 := NewClient(port);
    try
      CheckEqual(c2.WebSocketsUpgrade(WEBSOCKETS_KEY, Ajax, true), '',
        'WebSocketsUpgrade2');
      ServiceDefine(c2, '2');
      TestCallback(c2);
      if Relay then
      begin
        stats := OpenHttpGet('127.0.0.1', fPublicRelayPort, '/stats', '');
        check(PosEx('"version"', stats) > 0, 'stats');
      end;
      TestRest(c1);
      TestRest(c2);
    finally
      c2.Free;
    end;
  finally
    c1.Free;
  end;
end;

procedure TTestBidirectionalRemoteConnection.SOACallbackViaJSONWebsockets;
begin
  SOACallbackViaWebsockets({ajax=}true, {relay=}false);
end;

procedure TTestBidirectionalRemoteConnection.SOACallbackViaBinaryWebsockets;
begin
  SOACallbackViaWebsockets({ajax=}false, {relay=}false);
end;

procedure TTestBidirectionalRemoteConnection.RelayStart;
const
  RELAYKEY = 'aes256secret';
var
  stats: RawUTF8;
begin
  fPublicRelay := TPublicRelay.Create(nil, fPublicRelayClientsPort,
    fPublicRelayPort, RELAYKEY, TJWTHS256.Create('jwtsecret', 100, [], []));
  fPrivateRelay := TPrivateRelay.Create(nil, '127.0.0.1', fPublicRelayPort,
    RELAYKEY, fPublicRelay.ServerJWT.Compute([]), '127.0.0.1', HTTP_DEFAULTPORT,
    'X-Real-IP');
  check(not fPrivateRelay.Connected);
  check(fPrivateRelay.TryConnect);
  checkEqual(OpenHttpGet('127.0.0.1', fPublicRelayPort, '/invalid', ''), '', 'wrong URI');
  stats := OpenHttpGet('127.0.0.1', fPublicRelayPort, '/stats', '');
  check(PosEx('version', stats) > 0, 'stats');
end;

procedure TTestBidirectionalRemoteConnection.RelaySOACallbackViaJSONWebsockets;
begin
  SOACallbackViaWebsockets({ajax=}true, {relay=}true);
end;

procedure TTestBidirectionalRemoteConnection.RelayConnectionRecreate;
begin
  check(fPrivateRelay.TryConnect);
end;

procedure TTestBidirectionalRemoteConnection.RelaySOACallbackViaBinaryWebsockets;
begin
  SOACallbackViaWebsockets({ajax=}false, {relay=}true);
end;

procedure TTestBidirectionalRemoteConnection.RelayShutdown;
var
  stats: RaWUTF8;
begin
  stats := OpenHttpGet('127.0.0.1', fPublicRelayPort, '/stats', '');
  check(PosEx('"version"', stats) > 0, 'stats');
  fPrivateRelay.Free;
  sleep(100);
  stats := OpenHttpGet('127.0.0.1', fPublicRelayPort, '/stats', '');
  check(PosEx('"version"', stats) > 0, 'stats');
  fPublicRelay.Free;
end;

procedure TTestBidirectionalRemoteConnection._TRecordVersion;
begin
  TestMasterSlaveRecordVersion(Self, 'ws.db3');
end;

procedure TTestBidirectionalRemoteConnection.CleanUp;
begin
  FreeAndNil(fHttpServer);
  FreeAndNil(fServer);
end;


initialization
  _uE0 := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[0], 1);
  _uE7 := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[1], 1);
  _uE8 := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[2], 1);
  _uE9 := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[3], 1);
  _uEA := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[4], 1);
  _uF4 := WinAnsiToUtf8(@UTF8_E0_F4_BYTES[5], 1);

end.

