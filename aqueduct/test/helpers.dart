import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/query/mixin.dart';
export 'context_helpers.dart';

void justLogEverything() {
  hierarchicalLoggingEnabled = true;
  new Logger("")
    ..level = Level.ALL
    ..onRecord.listen((p) => print("$p ${p.object} ${p.stackTrace}"));
}

class TestUser extends ResourceOwner {
  int get uniqueIdentifier => id;
  @override
  int id;
}

class TestToken implements AuthToken, AuthCode {
  TestToken();

  TestToken.from(dynamic t) {
    if (t is TestToken) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..type = t.type
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..scopes = t.scopes
        ..requestedScopes = t.requestedScopes
        ..code = t.code;
    } else if (t is AuthToken) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..type = t.type
        ..accessToken = t.accessToken
        ..scopes = t.scopes
        ..refreshToken = t.refreshToken;
    } else if (t is AuthCode) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..requestedScopes = t.requestedScopes
        ..code = t.code;
    }
  }

  @override
  String accessToken;
  @override
  String refreshToken;
  @override
  DateTime issueDate;
  @override
  DateTime expirationDate;
  @override
  String type;
  @override
  dynamic resourceOwnerIdentifier;
  @override
  String clientID;
  @override
  String code;
  @override
  List<AuthScope> scopes;
  @override
  List<AuthScope> requestedScopes;

  @override
  bool get hasBeenExchanged => accessToken != null;

  @override
  set hasBeenExchanged(bool s) {}

  @override
  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  @override
  Map<String, dynamic> asMap() {
    var map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in": expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    return map;
  }
}

class InMemoryAuthStorage extends AuthServerDelegate {
  static const String DefaultPassword = "foobaraxegrind21%";

  InMemoryAuthStorage() {
    reset();
  }

  Map<String, AuthClient> clients;
  Map<int, TestUser> users = {};
  List<TestToken> tokens = [];

  void createUsers(int count) {
    for (int i = 0; i < count; i++) {
      var salt = AuthUtility.generateRandomSalt();
      var u = new TestUser()
        ..id = i + 1
        ..username = "bob+$i@stablekernel.com"
        ..salt = salt
        ..hashedPassword = AuthUtility.generatePasswordHash(DefaultPassword, salt);

      users[i + 1] = u;
    }
  }

  void reset() {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    clients = {
      "com.stablekernel.app1":
      new AuthClient("com.stablekernel.app1", AuthUtility.generatePasswordHash("kilimanjaro", salt), salt),
      "com.stablekernel.app2":
      new AuthClient("com.stablekernel.app2", AuthUtility.generatePasswordHash("fuji", salt), salt),
      "com.stablekernel.redirect": new AuthClient.withRedirectURI("com.stablekernel.redirect",
        AuthUtility.generatePasswordHash("mckinley", salt), salt, "http://stablekernel.com/auth/redirect"),
      "com.stablekernel.public": new AuthClient("com.stablekernel.public", null, salt),
      "com.stablekernel.redirect2": new AuthClient.withRedirectURI("com.stablekernel.redirect2",
        AuthUtility.generatePasswordHash("gibraltar", salt), salt, "http://stablekernel.com/auth/redirect2"),
      "com.stablekernel.scoped": new AuthClient.withRedirectURI("com.stablekernel.scoped",
        AuthUtility.generatePasswordHash("kilimanjaro", salt), salt, "http://stablekernel.com/auth/scoped",
        allowedScopes: [new AuthScope("user"), new AuthScope("other_scope")]),
    };
    users = {};
    tokens = [];
  }

  @override
  void addClient(AuthServer server, AuthClient client) {
    clients[client.id] = client;
  }

  @override
  void removeTokens(AuthServer server, dynamic identifier) {
    return tokens.removeWhere((t) => t.resourceOwnerIdentifier == identifier);
  }

  @override
  FutureOr<AuthToken> getToken(AuthServer server, {String byAccessToken, String byRefreshToken}) {
    AuthToken existing;
    if (byAccessToken != null) {
      existing = tokens.firstWhere((t) => t.accessToken == byAccessToken, orElse: () => null);
    } else if (byRefreshToken != null) {
      existing = tokens.firstWhere((t) => t.refreshToken == byRefreshToken, orElse: () => null);
    } else {
      throw new ArgumentError("byAccessToken and byRefreshToken are mutually exclusive");
    }

    if (existing == null) {
      return null;
    }
    return new TestToken.from(existing);
  }

  @override
  FutureOr<TestUser> getResourceOwner(AuthServer server, String username) {
    return users.values.firstWhere((t) => t.username == username, orElse: () => null);
  }

  @override
  void removeToken(AuthServer server, AuthCode code) => tokens.removeWhere((t) => t.code == code.code);

  @override
  FutureOr addToken(AuthServer server, AuthToken t, {AuthCode issuedFrom}) {
    if (issuedFrom != null) {
      var existingIssued = tokens.firstWhere((token) => token.code == issuedFrom?.code, orElse: () => null);
      var replacement = new TestToken.from(t);
      replacement.code = issuedFrom.code;
      replacement.scopes = issuedFrom.requestedScopes;

      tokens.remove(existingIssued);
      tokens.add(replacement);
    } else {
      tokens.add(new TestToken.from(t));
    }

    return null;
  }

  @override
  FutureOr updateToken(
      AuthServer server, String accessToken, String newAccessToken, DateTime newIssueDate, DateTime newExpirationDate) {
    var existing = tokens.firstWhere((e) => e.accessToken == accessToken, orElse: () => null);
    if (existing != null) {
      var replacement = new TestToken.from(existing)
        ..expirationDate = newExpirationDate
        ..issueDate = newIssueDate
        ..accessToken = newAccessToken
        ..clientID = existing.clientID
        ..refreshToken = existing.refreshToken
        ..resourceOwnerIdentifier = existing.resourceOwnerIdentifier
        ..type = existing.type;

      tokens.remove(existing);
      tokens.add(replacement);
    }

    return null;
  }

  @override
  void addCode(AuthServer server, AuthCode code) => tokens.add(new TestToken.from(code));

  @override
  FutureOr<AuthCode> getCode(AuthServer server, String code) {
    var existing = tokens.firstWhere((t) => t.code == code, orElse: () => null);
    if (existing == null) {
      return null;
    }
    return new TestToken.from(existing);
  }

  @override
  void removeCode(AuthServer server, String code) => tokens.removeWhere((c) => c.code == code);

  @override
  FutureOr<AuthClient> getClient(AuthServer server, String id) => clients[id];

  @override
  FutureOr removeClient(AuthServer server, String id) => clients.remove(id);
}

class DefaultPersistentStore extends PersistentStore {
  @override
  Query<T> newQuery<T extends ManagedObject>(ManagedContext context, ManagedEntity entity) {
    return new _MockQuery<T>.withEntity(context, entity);
  }

  @override
  Future<dynamic> execute(String sql, {Map<String, dynamic> substitutionValues}) async => null;

  @override
  Future<dynamic> executeQuery(String formatString, Map<String, dynamic> values, int timeoutInSeconds,
          {PersistentStoreQueryReturnType returnType}) async =>
      null;

  @override
  Future close() async {}

  @override
  Future<dynamic> transaction(ManagedContext transactionContext, Future queries(ManagedContext transaction)) async =>
      throw new Exception("Transaciton not supported on mock");

  @override
  List<String> createTable(SchemaTable t, {bool isTemporary: false}) => [];

  @override
  List<String> renameTable(SchemaTable table, String name) => [];

  @override
  List<String> deleteTable(SchemaTable table) => [];

  @override
  List<String> addTableUniqueColumnSet(SchemaTable table) => [];

  @override
  List<String> deleteTableUniqueColumnSet(SchemaTable table) => [];

  @override
  List<String> addColumn(SchemaTable table, SchemaColumn column, {String unencodedInitialValue}) => [];

  @override
  List<String> deleteColumn(SchemaTable table, SchemaColumn column) => [];

  @override
  List<String> renameColumn(SchemaTable table, SchemaColumn column, String name) => [];

  @override
  List<String> alterColumnNullability(SchemaTable table, SchemaColumn column, String unencodedInitialValue) => [];

  @override
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) => [];

  @override
  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) => [];

  @override
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) => [];

  @override
  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) => [];

  @override
  List<String> renameIndex(SchemaTable table, SchemaColumn column, String newIndexName) => [];

  @override
  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) => [];

  @override
  Future<int> get schemaVersion async => 0;

  @override
  Future<Schema> upgrade(Schema from, List<Migration> migrations, {bool temporary: false}) async {
    var out = from;
    for (var migration in migrations) {
      migration.database = new SchemaBuilder(this, out);
      await migration.upgrade();
      await migration.seed();
      out = migration.database.schema;
    }
   return out;
  }
}

class _MockQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  _MockQuery(this.context);

  _MockQuery.withEntity(this.context, ManagedEntity entity) {
    _entity = entity;
  }

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity => _entity ?? context.dataModel.entityForType(InstanceType);

  ManagedEntity _entity;

  @override
  Future<InstanceType> insert() async {
    throw new Exception("insert() in _MockQuery");
  }

  @override
  Future<List<InstanceType>> update() async {
    throw new Exception("update() in _MockQuery");
  }

  @override
  Future<InstanceType> updateOne() async {
    throw new Exception("updateOne() in _MockQuery");
  }

  @override
  Future<int> delete() async {
    throw new Exception("delete() in _MockQuery");
  }

  @override
  Future<List<InstanceType>> fetch() async {
    throw new Exception("fetch() in _MockQuery");
  }

  @override
  Future<InstanceType> fetchOne() async {
    throw new Exception("fetchOne() in _MockQuery");
  }

  @override
  QueryReduceOperation<InstanceType> get reduce {
    throw new Exception("fold in _MockQuery");
  }
}
