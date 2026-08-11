import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://pqroottrlhgkpcglnagf.supabase.co';
const _supabaseAnonKey = 'sb_publishable_YAOAdadWVWczdtAIlty1tw_N8lpHv52';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

bool _testMode = false;

void setTestMode(bool value) {
  _testMode = value;
}

bool _shouldUseSupabase() {
  return !_testMode;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class AppNotification {
  AppNotification({required this.recipientUsername, required this.message, this.isRead = false});

  final String recipientUsername;
  final String message;
  bool isRead;
}

class _MyAppState extends State<MyApp> {
  late final List<UserAccount> _users;
  late final List<Task> _tasks;
  late final List<FlatMember> _members;
  late final List<AppNotification> _notifications;
  final List<RoommateRentEntry> _roommateRentEntries = [];
  final List<RentEntry> _savedRentEntries = [];
  final List<MonthlyExpenseEntry> _monthlyExpenses = [];
  final List<ChatMessage> _chatMessages = [];
  final ValueNotifier<List<ChatMessage>> _chatMessagesNotifier = ValueNotifier(const []);

  UserAccount? _currentUser;
  bool _supabaseInitialized = false;
  bool _supabaseConnected = false;
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _taskChannel;
  int _debugUsersCount = 0;
  int _debugTasksCount = 0;
  int _debugMembersCount = 0;
  String _debugStatus = 'Initializing';

  bool get _isLoggedIn => _currentUser != null;

  String get _debugSummary {
    return 'Users: $_debugUsersCount • Tasks: $_debugTasksCount • Members: $_debugMembersCount • Status: $_debugStatus';
  }

  @override
  void initState() {
    super.initState();
    _users = [
      UserAccount(username: 'admin', password: '1234', role: 'admin'),
      UserAccount(username: 'asha', password: 'room123', role: 'roommate'),
      UserAccount(username: 'nimal', password: 'room123', role: 'roommate'),
    ];
    _tasks = [
      Task(
        title: 'Buy groceries',
        category: 'Shopping',
        priority: 'High',
        assignedTo: 'Asha',
      ),
      Task(
        title: 'Clean kitchen',
        category: 'Cleaning',
        priority: 'Medium',
        assignedTo: 'Nimal',
        completed: true,
      ),
      Task(
        title: 'Pay internet bill',
        category: 'Bills',
        priority: 'High',
        assignedTo: 'Admin',
      ),
    ];
    _members = [
      FlatMember(name: 'Admin', role: 'Owner'),
      FlatMember(name: 'Asha', role: 'Roommate'),
      FlatMember(name: 'Nimal', role: 'Roommate'),
    ];
    _notifications = [];
    if (_testMode) {
      _loadDemoData();
    }
    () async {
      await _loadRemoteData();
      await _ensureDefaultAdminUser();
    }();
  }

  Future<void> _ensureDefaultAdminUser() async {
    final adminUser = _users.firstWhere(
      (user) => user.username.toLowerCase() == 'admin',
      orElse: () => UserAccount(username: 'admin', password: '1234', role: 'admin'),
    );

    if (!_users.any((user) => user.username.toLowerCase() == 'admin')) {
      if (mounted) {
        setState(() {
          _users.add(adminUser);
        });
      } else {
        _users.add(adminUser);
      }
    }

    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      await _initializeSupabase();
      final client = Supabase.instance.client;
      final existing = await client.from('users').select().eq('username', 'admin');
      final rows = existing as List<dynamic>;

      if (rows.isEmpty) {
        final response = await client.from('users').insert({
          'username': 'admin',
          'password': '1234',
          'role': 'admin',
        }).select();
        final insertedRows = response as List<dynamic>;
        if (insertedRows.isNotEmpty) {
          final row = Map<String, dynamic>.from(insertedRows.first as Map);
          adminUser.id = row['id'] as int?;
        }
        _setSupabaseStatus('Admin user created in Supabase', connected: true);
        print('Created default admin user in Supabase');
      } else {
        print('Admin user already exists in Supabase');
      }
    } catch (error) {
      print('Failed to create default admin user: $error');
      _setSupabaseStatus('Admin user creation failed: $error', connected: false);
    }
  }

  void _login(UserAccount user) {
    setState(() {
      _currentUser = user;
      _debugStatus = 'Logged in as ${user.username}';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showPendingNotifications(user);
    });
  }

  void _showPendingNotifications(UserAccount user) {
    final pending = _notifications.where((notification) {
      return !notification.isRead && notification.recipientUsername.toLowerCase() == user.username.toLowerCase();
    }).toList();

    if (pending.isEmpty) {
      return;
    }

    setState(() {
      for (final notification in pending) {
        notification.isRead = true;
      }
    });

    final message = pending.length == 1
        ? pending.first.message
        : '${pending.length} new task updates are waiting for you.';

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      print('Skipped snackbar because no ScaffoldMessenger is available yet.');
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _addNotification({required String recipientUsername, required String message}) {
    final normalized = recipientUsername.trim();
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _notifications.add(AppNotification(recipientUsername: normalized, message: message));
    });
  }

  void _addRentEntry(RoommateRentEntry entry) {
    setState(() {
      _roommateRentEntries.add(entry);
    });
  }

  void _handleRentEntrySaved(RentEntry entry) {
    _saveRentData(entry);
  }

  void _handleMonthlyExpenseSaved(MonthlyExpenseEntry entry) {
    _saveMonthlyExpenseData(entry);
  }

  void _logout() {
    setState(() {
      _currentUser = null;
      _debugStatus = 'Logged out';
    });
  }

  void _setSupabaseStatus(String message, {required bool connected}) {
    if (!mounted) {
      return;
    }

    setState(() {
      _supabaseConnected = connected;
      _debugStatus = message;
    });
    print('Supabase status: $message');
  }

  Future<bool> _initializeSupabase() async {
    if (_supabaseInitialized && _supabaseConnected) {
      return true;
    }
    if (!_shouldUseSupabase()) {
      return false;
    }

    try {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
      _supabaseInitialized = true;
      _supabaseConnected = true;
      _setSupabaseStatus('Supabase connected', connected: true);
      _subscribeToChatUpdates();
      _subscribeToTaskUpdates();
      return true;
    } catch (error) {
      _supabaseInitialized = true;
      _supabaseConnected = false;
      _setSupabaseStatus('Supabase error: $error', connected: false);
      return false;
    }
  }

  Future<void> _loadRemoteData() async {
    try {
      print('Attempting to load data from Supabase...');
      final connected = await _initializeSupabase();
      if (!connected) {
        throw Exception('Supabase not initialized');
      }
      final client = Supabase.instance.client;
      final usersResponse = await client.from('users').select() as List<dynamic>;
      final tasksResponse = await client.from('tasks').select() as List<dynamic>;
      final membersResponse = await client.from('flat_members').select() as List<dynamic>;
      final rentEntriesResponse = await client.from('rent_entries').select() as List<dynamic>;
      final monthlyExpensesResponse = await client.from('monthly_expenses').select() as List<dynamic>;

      if (!mounted) {
        return;
      }

      setState(() {
        _debugUsersCount = usersResponse.length;
        if (usersResponse.isNotEmpty) {
          _users
            ..clear()
            ..addAll(_parseUsers(usersResponse));
        }
        _debugTasksCount = tasksResponse.length;
        if (tasksResponse.isNotEmpty) {
          _tasks
            ..clear()
            ..addAll(_parseTasks(tasksResponse));
        }
        _debugMembersCount = membersResponse.length;
        if (membersResponse.isNotEmpty) {
          _members
            ..clear()
            ..addAll(_parseMembers(membersResponse));
        }
        _savedRentEntries
          ..clear()
          ..addAll(_parseRentEntries(rentEntriesResponse));
        _monthlyExpenses
          ..clear()
          ..addAll(_parseMonthlyExpenses(monthlyExpensesResponse));
        _debugStatus = 'Loaded $_debugUsersCount users / $_debugTasksCount tasks / $_debugMembersCount members';
      });
      await _loadChatMessages();
      print('Supabase load succeeded: $_debugUsersCount users / $_debugTasksCount tasks / $_debugMembersCount members');
      _rebuildRoommateRentEntries();
    } catch (error) {
      print('Supabase load failed: $error');
      if (mounted) {
        setState(() {
          _debugStatus = 'Offline demo mode';
          _supabaseConnected = false;
          _loadDemoData();
        });
      }
    }
  }

  void _loadDemoData() {
    _users
      ..clear()
      ..addAll([
        UserAccount(username: 'admin', password: 'admin123', role: 'admin'),
        UserAccount(username: 'rahul', password: 'rahul123', role: 'roommate'),
        UserAccount(username: 'priya', password: 'priya123', role: 'roommate'),
      ]);
    _tasks
      ..clear()
      ..addAll([
        Task(title: 'Clean kitchen', category: 'Cleaning', priority: 'High', assignedTo: 'rahul', status: 'Planned'),
        Task(title: 'Pay electricity bill', category: 'Bills', priority: 'High', assignedTo: 'priya', status: 'Planned'),
        Task(title: 'Buy groceries', category: 'Shopping', priority: 'Medium', assignedTo: 'rahul', status: 'Started'),
      ]);
    _members
      ..clear()
      ..addAll([
        FlatMember(name: 'Rahul', role: 'Roommate'),
        FlatMember(name: 'Priya', role: 'Roommate'),
      ]);
    _savedRentEntries.clear();
    _monthlyExpenses
      ..clear()
      ..addAll([
        MonthlyExpenseEntry(title: 'Electricity', amount: 1500, category: 'Bills', monthLabel: '2026-08'),
        MonthlyExpenseEntry(title: 'Internet', amount: 999, category: 'Bills', monthLabel: '2026-08'),
      ]);
    _chatMessages.clear();
    _rebuildRoommateRentEntries();
  }

  Future<void> _createUser(String username, String password) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedPassword = password.trim();

    if (normalizedUsername.isEmpty || normalizedPassword.isEmpty) {
      return;
    }

    final alreadyExists = _users.any((user) => user.username.toLowerCase() == normalizedUsername);
    if (alreadyExists) {
      return;
    }

    final newUser = UserAccount(username: normalizedUsername, password: normalizedPassword, role: 'roommate');
    setState(() {
      _users.add(newUser);
      _members.add(FlatMember(name: _formatMemberName(normalizedUsername), role: 'Roommate'));
    });

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        throw Exception('Supabase not initialized');
      }
      final client = Supabase.instance.client;
      print('Saving new user to Supabase: $normalizedUsername');
      final response = await client.from('users').insert({
        'username': normalizedUsername,
        'password': normalizedPassword,
        'role': 'roommate',
      }).select();
      final rows = response as List<dynamic>;
      if (rows.isNotEmpty) {
        final row = Map<String, dynamic>.from(rows.first as Map);
        newUser.id = row['id'] as int?;
      }
      await client.from('flat_members').insert({
        'name': _formatMemberName(normalizedUsername),
        'role': 'Roommate',
      });
      _setSupabaseStatus('Saved user to Supabase', connected: true);
      print('User saved to Supabase successfully');
    } catch (error) {
      print('Failed to save user to Supabase: $error');
      _setSupabaseStatus('Failed to save user: $error', connected: false);
    }
  }

  Future<void> _saveRentData(RentEntry entry) async {
    setState(() {
      _savedRentEntries.add(entry);
      _rebuildRoommateRentEntries();
    });
    await _saveRentEntryToDatabase(entry);
  }

  Future<void> _saveMonthlyExpenseData(MonthlyExpenseEntry entry) async {
    setState(() {
      _monthlyExpenses.add(entry);
    });
    await _saveMonthlyExpenseToDatabase(entry);
  }

  void _rebuildRoommateRentEntries() {
    _roommateRentEntries
      ..clear()
      ..addAll(_savedRentEntries.expand((entry) {
        return entry.memberAmounts.entries.map((pair) {
          final amount = double.tryParse(pair.value) ?? 0;
          return RoommateRentEntry(
            username: pair.key,
            monthLabel: entry.monthLabel,
            rent: entry.totalRent,
            expenses: entry.totalExpenses,
            totalAmount: amount,
          );
        });
      }));
  }

  Future<void> _saveRentEntryToDatabase(RentEntry entry) async {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        throw Exception('Supabase not initialized');
      }
      final client = Supabase.instance.client;
      await client.from('rent_entries').insert({
        'month_label': entry.monthLabel,
        'total_rent': entry.totalRent,
        'total_expenses': entry.totalExpenses,
        'member_amounts': entry.memberAmounts,
      });
      _setSupabaseStatus('Saved rent entry to Supabase', connected: true);
    } catch (error) {
      print('Failed to save rent entry to Supabase: $error');
      _setSupabaseStatus('Failed to save rent entry: $error', connected: false);
    }
  }

  Future<void> _saveMonthlyExpenseToDatabase(MonthlyExpenseEntry entry) async {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        throw Exception('Supabase not initialized');
      }
      final client = Supabase.instance.client;
      final response = await client.from('monthly_expenses').insert({
        'title': entry.title,
        'amount': entry.amount,
        'category': entry.category,
        'month_label': entry.monthLabel,
        'deleted': entry.deleted,
      }).select() as List<dynamic>;

      if (response.isNotEmpty) {
        final row = Map<String, dynamic>.from(response.first as Map);
        entry.id = row['id'] as int?;
      }

      _setSupabaseStatus('Saved monthly expense to Supabase', connected: true);
    } catch (error) {
      print('Failed to save monthly expense to Supabase: $error');
      _setSupabaseStatus('Failed to save monthly expense: $error', connected: false);
    }
  }

  Future<void> _loadChatMessages() async {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return;
      }

      final client = Supabase.instance.client;
      final response = await client
          .from('chat_messages')
          .select()
          .order('created_at', ascending: true) as List<dynamic>;

      if (!mounted) {
        return;
      }

      setState(() {
        _chatMessages
          ..clear()
          ..addAll(_parseChatMessages(response));
        _chatMessagesNotifier.value = List<ChatMessage>.unmodifiable(_chatMessages);
      });
    } catch (error) {
      print('Failed to load chat messages from Supabase: $error');
      if (mounted) {
        setState(() {
          _supabaseConnected = false;
          _debugStatus = 'Chat load failed: $error';
        });
      }
    }
  }

  Future<bool> _verifyStorageBucket(String bucketId) async {
    if (!_shouldUseSupabase()) {
      return false;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return false;
      }

      final client = Supabase.instance.client;
      await client.storage.from(bucketId).list();
      final exists = true;
      print('Storage bucket "$bucketId" exists: $exists');
      return exists;
    } catch (e) {
      print('Storage bucket "$bucketId" check failed: $e');
      return false;
    }
  }

  Future<String?> _uploadTaskImage(Task task, XFile imageFile) async {
    if (!_shouldUseSupabase()) {
      return null;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return 'Not connected to Supabase';
      }

      final bucketExists = await _verifyStorageBucket('task-images');
      if (!bucketExists) {
        return 'Storage bucket "task-images" not found. Create it in Supabase Dashboard > Storage.';
      }

      final bytes = await imageFile.readAsBytes();
      final fileName = 'task_${task.id ?? DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      await Supabase.instance.client.storage
          .from('task-images')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
      final publicUrl = Supabase.instance.client.storage
          .from('task-images')
          .getPublicUrl(fileName);

      setState(() {
        task.imageUrl = publicUrl;
      });

      if (task.id != null) {
        await _updateTaskInSupabase(task);
      }

      return null;
    } catch (e) {
      return 'Image upload failed: $e';
    }
  }

  Future<void> _updateTaskInSupabase(Task task) async {
    if (!_shouldUseSupabase() || task.id == null) {
      return;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return;
      }

      final client = Supabase.instance.client;
      await client.from('tasks').update({
        'title': task.title,
        'category': task.category,
        'priority': task.priority,
        'assigned_to': task.assignedTo,
        'completed': task.completed,
        'status': task.status,
        'image_url': task.imageUrl,
      }).eq('id', task.id!);
    } catch (e) {
      print('Failed to update task in Supabase: $e');
    }
  }

  void _subscribeToChatUpdates() {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      _chatChannel?.unsubscribe();
      _chatChannel = client
          .channel('chat_messages')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            callback: (payload) async {
              await _loadChatMessages();
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              print('Chat subscription issue: $status $error');
            }
          });
    } catch (error) {
      print('Failed to subscribe to chat updates: $error');
    }
  }

  Future<String?> _sendChatMessage({
    required String senderUsername,
    required String recipientUsername,
    required String content,
    XFile? imageFile,
  }) async {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty && imageFile == null) {
      return null;
    }

    String? uploadedImageUrl;

    if (imageFile != null) {
      try {
        final bucketExists = await _verifyStorageBucket('chat-images');
        if (!bucketExists) {
          return 'Storage bucket "chat-images" not found. Create it in Supabase Dashboard > Storage.';
        }

        final bytes = await imageFile.readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
        await Supabase.instance.client.storage
            .from('chat-images')
            .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
        uploadedImageUrl = Supabase.instance.client.storage
            .from('chat-images')
            .getPublicUrl(fileName);
      } catch (e) {
        return 'Image upload failed: $e';
      }
    }

    final message = ChatMessage(
      senderUsername: senderUsername,
      recipientUsername: recipientUsername,
      content: trimmedContent,
      imageUrl: uploadedImageUrl,
      createdAt: DateTime.now().toUtc(),
      isRead: false,
    );

    setState(() {
      _chatMessages.add(message);
      _chatMessagesNotifier.value = List<ChatMessage>.unmodifiable(_chatMessages);
    });

    if (!_shouldUseSupabase()) {
      return null;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return 'Not connected to Supabase';
      }

      final client = Supabase.instance.client;
      final response = await client.from('chat_messages').insert({
        'sender_username': message.senderUsername,
        'recipient_username': message.recipientUsername,
        'content': message.content,
        if (message.imageUrl != null) 'image_url': message.imageUrl,
        'is_read': message.isRead,
      }).select() as List<dynamic>;

      if (response.isNotEmpty) {
        final inserted = ChatMessage.fromMap(Map<String, dynamic>.from(response.first as Map));
        if (mounted) {
          setState(() {
            message.id = inserted.id;
            message.createdAt = inserted.createdAt;
            message.isRead = inserted.isRead;
          });
        }
      }
      return null;
    } catch (error) {
      return 'Failed to send message: $error';
    }
  }

  List<ChatMessage> _parseChatMessages(List<dynamic> rows) {
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return ChatMessage.fromMap(data);
    }).toList();
  }

  List<ChatMessage> get _sortedChatMessages {
    final messages = List<ChatMessage>.from(_chatMessages);
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  List<ChatMessage> _messagesBetween(String first, String second) {
    final lowerFirst = first.toLowerCase();
    final lowerSecond = second.toLowerCase();
    return _sortedChatMessages.where((message) {
      final sender = message.senderUsername.toLowerCase();
      final recipient = message.recipientUsername.toLowerCase();
      return (sender == lowerFirst && recipient == lowerSecond) ||
          (sender == lowerSecond && recipient == lowerFirst);
    }).toList();
  }

  Future<void> _markMessagesRead(String viewerUsername, String peerUsername) async {
    if (!_shouldUseSupabase()) {
      setState(() {
        for (final message in _chatMessages) {
          if (message.recipientUsername.toLowerCase() == viewerUsername.toLowerCase() &&
              message.senderUsername.toLowerCase() == peerUsername.toLowerCase()) {
            message.isRead = true;
          }
        }
        _chatMessagesNotifier.value = List<ChatMessage>.unmodifiable(_chatMessages);
      });
      return;
    }

    try {
      final connected = await _initializeSupabase();
      if (!connected) {
        return;
      }

      final client = Supabase.instance.client;
      await client
          .from('chat_messages')
          .update({'is_read': true})
          .eq('recipient_username', viewerUsername)
          .eq('sender_username', peerUsername)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          for (final message in _chatMessages) {
            if (message.recipientUsername.toLowerCase() == viewerUsername.toLowerCase() &&
                message.senderUsername.toLowerCase() == peerUsername.toLowerCase()) {
              message.isRead = true;
            }
          }
        });
      }
    } catch (error) {
      print('Failed to mark chat messages as read: $error');
    }
  }

  void _openChat(BuildContext context, String peerUsername) {
    if (_currentUser == null) {
      return;
    }

    final currentUser = _currentUser!;
    final conversation = _messagesBetween(currentUser.username, peerUsername);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) {
        return ChatPage(
          currentUser: currentUser,
          peerUsername: peerUsername,
          initialMessages: conversation,
          chatMessagesNotifier: _chatMessagesNotifier,
          onSendMessage: (content, {XFile? imageFile}) async {
            final error = await _sendChatMessage(
              senderUsername: currentUser.username,
              recipientUsername: peerUsername,
              content: content,
              imageFile: imageFile,
            );
            return error;
          },
          onChatOpened: () async {
            await _markMessagesRead(currentUser.username, peerUsername);
            await _loadChatMessages();
          },
        );
      },
    ));
  }

  void _subscribeToTaskUpdates() {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      _taskChannel?.unsubscribe();
      _taskChannel = client
          .channel('tasks')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tasks',
            callback: (payload) async {
              await _loadRemoteData();
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              print('Task subscription issue: $status $error');
            }
          });
    } catch (error) {
      print('Failed to subscribe to task updates: $error');
    }
  }

  void _disposeTaskChannel() {
    _taskChannel?.unsubscribe();
    _taskChannel = null;
  }

  void _disposeChatChannel() {
    _chatChannel?.unsubscribe();
    _chatChannel = null;
  }

  @override
  void dispose() {
    _disposeChatChannel();
    _disposeTaskChannel();
    super.dispose();
  }

  List<UserAccount> _parseUsers(List<dynamic> rows) {
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return UserAccount(
        id: data['id'] as int?,
        username: data['username']?.toString() ?? '',
        password: data['password']?.toString() ?? '',
        role: data['role']?.toString() ?? 'roommate',
      );
    }).toList();
  }

  List<Task> _parseTasks(List<dynamic> rows) {
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return Task(
        id: data['id'] as int?,
        title: data['title']?.toString() ?? '',
        category: data['category']?.toString() ?? 'General',
        priority: data['priority']?.toString() ?? 'Medium',
        assignedTo: data['assigned_to']?.toString(),
        completed: data['completed'] == true,
        status: data['status']?.toString() ?? 'Planned',
        imageUrl: data['image_url'] as String?,
      );
    }).toList();
  }

  List<FlatMember> _parseMembers(List<dynamic> rows) {
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return FlatMember(
        id: data['id'] as int?,
        name: data['name']?.toString() ?? '',
        role: data['role']?.toString() ?? 'Roommate',
      );
    }).toList();
  }

  List<RentEntry> _parseRentEntries(List<dynamic> rows) {
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      final memberAmountJson = data['member_amounts'];
      final amounts = <String, String>{};
      if (memberAmountJson is Map) {
        memberAmountJson.forEach((key, value) {
          amounts[key.toString()] = value?.toString() ?? '0';
        });
      }
      return RentEntry(
        monthLabel: data['month_label']?.toString() ?? '',
        totalRent: double.tryParse(data['total_rent']?.toString() ?? '0') ?? 0,
        totalExpenses: double.tryParse(data['total_expenses']?.toString() ?? '0') ?? 0,
        memberAmounts: amounts,
      );
    }).toList();
  }

  List<MonthlyExpenseEntry> _parseMonthlyExpenses(List<dynamic> rows) {
    final all = rows.map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return MonthlyExpenseEntry(
        id: data['id'] as int?,
        title: data['title']?.toString() ?? '',
        amount: double.tryParse(data['amount']?.toString() ?? '0') ?? 0,
        category: data['category']?.toString() ?? 'Other',
        monthLabel: data['month_label']?.toString() ?? '',
        deleted: data['deleted'] == true,
      );
    }).toList();
    return all.where((entry) => !entry.deleted).toList();
  }

  String _formatMemberName(String value) {
    final words = value.split(RegExp(r'[_\s-]+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) {
      return 'Roommate';
    }
    return words.map((word) {
      if (word.length <= 1) {
        return word.toUpperCase();
      }
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bachelor Flat Task Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black87,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            side: BorderSide(color: Colors.teal.shade300),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
      home: _isLoggedIn
          ? (_currentUser!.role == 'admin'
              ? TaskManagementHome(
                  currentUser: _currentUser!,
                  onLogout: _logout,
                  users: _users,
                  tasks: _tasks,
                  members: _members,
                  onCreateUser: _createUser,
                  debugSummary: _debugSummary,
                  onAssignTask: (recipientUsername, taskTitle) {
                    _addNotification(
                      recipientUsername: recipientUsername,
                      message: 'You have been assigned a new task: $taskTitle',
                    );
                  },
                  rentEntries: _roommateRentEntries,
                  savedRentEntries: _savedRentEntries,
                  monthlyExpenses: _monthlyExpenses,
                  onRentEntryAdded: _addRentEntry,
                  onRentEntrySaved: _handleRentEntrySaved,
                  onMonthlyExpenseSaved: _handleMonthlyExpenseSaved,
                  chatMessages: _chatMessages,
                  onOpenChat: (context, peerUsername) => _openChat(context, peerUsername),
                )
              : RoommateHome(
                  currentUser: _currentUser!,
                  onLogout: _logout,
                  tasks: _tasks,
                  members: _members,
                  notifications: _notifications,
                  rentEntries: _roommateRentEntries,
                  chatMessages: _chatMessages,
                  onOpenChat: (context, peerUsername) => _openChat(context, peerUsername),
                  onTaskImageUpdated: (task, imageFile) => _uploadTaskImage(task, imageFile),
                ))
          : LoginPage(
              onLogin: _login,
              users: _users,
              supabaseStatus: _debugStatus,
              isSupabaseConnected: _supabaseConnected,
            ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLogin,
    required this.users,
    required this.supabaseStatus,
    required this.isSupabaseConnected,
  });

  final ValueChanged<UserAccount> onLogin;
  final List<UserAccount> users;
  final String supabaseStatus;
  final bool isSupabaseConnected;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _errorMessage = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitLogin() {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (username == 'admin' && password == '1234') {
      widget.onLogin(UserAccount(username: 'admin', password: '1234', role: 'admin'));
      return;
    }

    for (final user in widget.users) {
      if (user.username.toLowerCase() == username && user.password == password) {
        widget.onLogin(user);
        return;
      }
    }

    setState(() {
      _errorMessage = 'Invalid credentials. Try admin / 1234 or a created roommate account.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.teal.shade100,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Icon(Icons.home_outlined, size: 36, color: Colors.teal.shade700),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Flatmates Login',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Secure access for admin and roommates with shared rent and expense tracking.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: widget.isSupabaseConnected
                              ? Colors.teal.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          widget.isSupabaseConnected
                              ? 'Supabase connected • ${widget.supabaseStatus}'
                              : 'Supabase disconnected • ${widget.supabaseStatus}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: widget.isSupabaseConnected ? Colors.teal.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitLogin,
                          child: const Text('Login'),
                        ),
                      ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Use admin / 1234 or any created roommate account.',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UserAccount {
  UserAccount({this.id, required this.username, required this.password, required this.role});

  int? id;
  final String username;
  final String password;
  final String role;
}

class Task {
  Task({
    this.id,
    required this.title,
    required this.category,
    required this.priority,
    this.assignedTo,
    this.completed = false,
    this.status = 'Planned',
    this.imageUrl,
  });

  int? id;
  final String title;
  final String category;
  final String priority;
  final String? assignedTo;
  bool completed;
  String status;
  String? imageUrl;
}

class FlatMember {
  FlatMember({this.id, required this.name, required this.role});

  int? id;
  final String name;
  final String role;
}

class RentEntry {
  RentEntry({required this.monthLabel, required this.totalRent, required this.totalExpenses, required this.memberAmounts});

  final String monthLabel;
  final double totalRent;
  final double totalExpenses;
  final Map<String, String> memberAmounts;
}

class MonthlyExpenseEntry {
  MonthlyExpenseEntry({this.id, required this.title, required this.amount, required this.category, required this.monthLabel, this.deleted = false});

  int? id;
  final String title;
  final double amount;
  final String category;
  final String monthLabel;
  bool deleted;
}

class RoommateRentEntry {
  RoommateRentEntry({
    required this.username,
    required this.monthLabel,
    required this.rent,
    required this.expenses,
    required this.totalAmount,
  });

  final String username;
  final String monthLabel;
  final double rent;
  final double expenses;
  final double totalAmount;
}

class ChatMessage {
  ChatMessage({
    this.id,
    required this.senderUsername,
    required this.recipientUsername,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.isRead = false,
  });

  int? id;
  final String senderUsername;
  final String recipientUsername;
  final String content;
  final String? imageUrl;
  DateTime createdAt;
  bool isRead;

  factory ChatMessage.fromMap(Map<String, dynamic> data) {
    final createdAtValue = data['created_at'];
    DateTime createdAt;

    if (createdAtValue is String) {
      createdAt = DateTime.tryParse(createdAtValue) ?? DateTime.now().toUtc();
    } else if (createdAtValue is DateTime) {
      createdAt = createdAtValue.toUtc();
    } else {
      createdAt = DateTime.now().toUtc();
    }

    return ChatMessage(
      id: data['id'] as int?,
      senderUsername: data['sender_username']?.toString() ?? '',
      recipientUsername: data['recipient_username']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      imageUrl: data['image_url'] as String?,
      createdAt: createdAt,
      isRead: data['is_read'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sender_username': senderUsername,
      'recipient_username': recipientUsername,
      'content': content,
      if (imageUrl != null) 'image_url': imageUrl,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_read': isRead,
    };
  }
}

class TaskManagementHome extends StatefulWidget {
  const TaskManagementHome({
    super.key,
    required this.currentUser,
    required this.onLogout,
    required this.users,
    required this.tasks,
    required this.members,
    required this.onCreateUser,
    required this.debugSummary,
    required this.onAssignTask,
    required this.rentEntries,
    required this.savedRentEntries,
    required this.monthlyExpenses,
    required this.onRentEntryAdded,
    required this.onRentEntrySaved,
    required this.onMonthlyExpenseSaved,
    required this.chatMessages,
    required this.onOpenChat,
  });

  final UserAccount currentUser;
  final VoidCallback onLogout;
  final List<UserAccount> users;
  final List<Task> tasks;
  final List<FlatMember> members;
  final void Function(String username, String password) onCreateUser;
  final String debugSummary;
  final void Function(String recipientUsername, String taskTitle) onAssignTask;
  final List<RoommateRentEntry> rentEntries;
  final List<RentEntry> savedRentEntries;
  final List<MonthlyExpenseEntry> monthlyExpenses;
  final ValueChanged<RoommateRentEntry> onRentEntryAdded;
  final ValueChanged<RentEntry> onRentEntrySaved;
  final ValueChanged<MonthlyExpenseEntry> onMonthlyExpenseSaved;
  final List<ChatMessage> chatMessages;
  final void Function(BuildContext context, String peerUsername) onOpenChat;

  @override
  State<TaskManagementHome> createState() => _TaskManagementHomeState();
}

class _TaskManagementHomeState extends State<TaskManagementHome> {
  String _selectedFilter = 'All';
  String _selectedAdminTab = 'Dashboard';
  final TextEditingController _totalRentController = TextEditingController(text: '14000');
  String _selectedRentMonth = '';
  final List<String> _selectedRentMembers = [];
  final Map<String, TextEditingController> _rentControllersByMember = {};
  final Map<String, String> _rentValuesByMember = {};
  final List<RentEntry> _savedRentEntries = [];
  final List<MonthlyExpenseEntry> _monthlyExpenseEntries = [];
  final Set<String> _distributedMembers = {};
  final Set<String> _receivedMembers = {};
  final TextEditingController _expenseTitleController = TextEditingController();
  final TextEditingController _expenseAmountController = TextEditingController();
  String _selectedExpenseMonth = '';
  String _selectedExpenseCategory = 'Gas';

  List<Task> get _visibleTasks {
    return widget.tasks.where((task) {
      if (_selectedFilter == 'Pending') return !task.completed;
      if (_selectedFilter == 'Done') return task.completed;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _syncRentSelectionMembers();
    _savedRentEntries
      ..clear()
      ..addAll(widget.savedRentEntries);
    _monthlyExpenseEntries
      ..clear()
      ..addAll(widget.monthlyExpenses);
  }

  @override
  void didUpdateWidget(covariant TaskManagementHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRentSelectionMembers();
    if (!listEquals(widget.savedRentEntries, oldWidget.savedRentEntries)) {
      _savedRentEntries
        ..clear()
        ..addAll(widget.savedRentEntries);
    }
    if (!listEquals(widget.monthlyExpenses, oldWidget.monthlyExpenses)) {
      _monthlyExpenseEntries
        ..clear()
        ..addAll(widget.monthlyExpenses);
    }
  }

  @override
  void dispose() {
    for (final controller in _rentControllersByMember.values) {
      controller.dispose();
    }
    _totalRentController.dispose();
    _expenseTitleController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  void _syncRentSelectionMembers() {
    final availableMembers = widget.members.where((member) => member.name != 'Admin').map((member) => member.name).toSet();
    final keptMembers = _selectedRentMembers.where(availableMembers.contains).toList();

    for (final memberName in availableMembers) {
      if (!keptMembers.contains(memberName)) {
        keptMembers.add(memberName);
      }
    }

    if (_selectedRentMembers.length != keptMembers.length || !listEquals(_selectedRentMembers, keptMembers)) {
      _selectedRentMembers
        ..clear()
        ..addAll(keptMembers);
    }
  }

  void _ensureRentController(String memberName, String initialValue) {
    if (_rentControllersByMember.containsKey(memberName)) {
      return;
    }

    final controller = TextEditingController(text: initialValue);
    _rentControllersByMember[memberName] = controller;
    _rentValuesByMember[memberName] = initialValue;
  }

  String _formatMonth(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.year}';
  }

  List<String> _buildMonthOptions() {
    final now = DateTime.now();
    return List.generate(12, (index) {
      final monthDate = DateTime(now.year, now.month + index);
      return _formatMonth(monthDate);
    });
  }

  double get _monthlyExpensesTotal {
    return _monthlyExpenseEntries.fold<double>(0, (sum, entry) => sum + entry.amount);
  }

  double get _sharedCostTotal {
    final rent = double.tryParse(_totalRentController.text) ?? 0;
    return rent + _monthlyExpensesTotal;
  }

  double get _currentSplitAmount {
    final count = _selectedRentMembers.length;
    if (count == 0 || _sharedCostTotal <= 0) {
      return 0;
    }
    return _sharedCostTotal / count;
  }

  void _applyEqualSplit() {
    final splitValue = _currentSplitAmount.toStringAsFixed(0);
    for (final memberName in _selectedRentMembers) {
      if (!_rentControllersByMember.containsKey(memberName)) {
        _ensureRentController(memberName, splitValue);
      } else {
        _rentControllersByMember[memberName]!.text = splitValue;
      }
      _rentValuesByMember[memberName] = splitValue;
    }
    setState(() {});
  }

  void _saveRentEntry() {
    if (_selectedRentMembers.isEmpty) {
      return;
    }

    final total = double.tryParse(_totalRentController.text) ?? 0;
    final amounts = <String, String>{};
    for (final memberName in _selectedRentMembers) {
      amounts[memberName] = _rentValuesByMember[memberName] ?? _currentSplitAmount.toStringAsFixed(0);
    }

    final monthLabel = _selectedRentMonth.isEmpty ? _formatMonth(DateTime.now()) : _selectedRentMonth;

    final rentEntry = RentEntry(
      monthLabel: monthLabel,
      totalRent: total,
      totalExpenses: _monthlyExpensesTotal,
      memberAmounts: amounts,
    );

    setState(() {
      _savedRentEntries.add(rentEntry);
    });

    for (final memberName in _selectedRentMembers) {
      final amountText = amounts[memberName] ?? _currentSplitAmount.toStringAsFixed(0);
      final amount = double.tryParse(amountText) ?? 0;
      widget.onRentEntryAdded(
        RoommateRentEntry(
          username: memberName,
          monthLabel: monthLabel,
          rent: total,
          expenses: _monthlyExpensesTotal,
          totalAmount: amount,
        ),
      );
    }

    widget.onRentEntrySaved(rentEntry);
  }

  void _saveMonthlyExpense() {
    final title = _expenseTitleController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text) ?? 0;
    final month = _selectedExpenseMonth.isEmpty ? _formatMonth(DateTime.now()) : _selectedExpenseMonth;

    if (title.isEmpty || amount <= 0) {
      return;
    }

    final expenseEntry = MonthlyExpenseEntry(
      title: title,
      amount: amount,
      category: _selectedExpenseCategory,
      monthLabel: month,
    );

    setState(() {
      _monthlyExpenseEntries.add(expenseEntry);
      _expenseTitleController.clear();
      _expenseAmountController.clear();
    });

    widget.onMonthlyExpenseSaved(expenseEntry);
  }

  Future<void> _removeMonthlyExpense(MonthlyExpenseEntry entry) async {
    // Soft delete locally first for immediate feedback
    setState(() {
      entry.deleted = true;
    });

    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      try {
        await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
      } catch (_) {
        // ignore if already initialized
      }

      final client = Supabase.instance.client;

      if (entry.id != null) {
        await client.from('monthly_expenses').update({'deleted': true}).eq('id', entry.id!);
      } else {
        // Fallback: try to update by matching fields
        await client.from('monthly_expenses').update({'deleted': true}).match({
          'title': entry.title,
          'month_label': entry.monthLabel,
          'amount': entry.amount,
        });
      }

      _setSupabaseStatus('Soft deleted monthly expense from Supabase', connected: true);
    } catch (error) {
      print('Failed to soft delete monthly expense from Supabase: $error');
      _setSupabaseStatus('Failed to soft delete monthly expense: $error', connected: false);
    }
  }

  void _setSupabaseStatus(String message, {required bool connected}) {
    print('Supabase status: $message');
    if (!mounted) {
      return;
    }
    setState(() {
      // Keep the UI responsive even though the admin view does not display this status directly.
    });
  }

  int get _pendingCount => widget.tasks.where((task) => !task.completed).length;
  int get _doneCount => widget.tasks.where((task) => task.completed).length;

  Future<void> _syncTask(Task task, {required bool isNew}) async {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
      final client = Supabase.instance.client;
      if (isNew) {
        print('Saving new task to Supabase: ${task.title}');
        final response = await client.from('tasks').insert({
          'title': task.title,
          'category': task.category,
          'priority': task.priority,
          'assigned_to': task.assignedTo,
          'completed': task.completed,
          'status': task.status,
          if (task.imageUrl != null) 'image_url': task.imageUrl,
        }).select();
        final rows = response as List<dynamic>;
        if (rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map);
          task.id = row['id'] as int?;
        }
      } else if (task.id != null) {
        print('Updating task in Supabase: ${task.title}');
        await client.from('tasks').update({
          'title': task.title,
          'category': task.category,
          'priority': task.priority,
          'assigned_to': task.assignedTo,
          'completed': task.completed,
          'status': task.status,
          if (task.imageUrl != null) 'image_url': task.imageUrl,
        }).eq('id', task.id!);
      }
      _setSupabaseStatus('Task synced to Supabase', connected: true);
    } catch (error) {
      print('Failed to sync task to Supabase: $error');
      _setSupabaseStatus('Task sync failed: $error', connected: false);
    }
  }

  Future<void> _syncMember(FlatMember member, {required bool isNew}) async {
    if (!_shouldUseSupabase()) {
      return;
    }

    try {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
      final client = Supabase.instance.client;
      if (isNew) {
        print('Saving member to Supabase: ${member.name}');
        final response = await client.from('flat_members').insert({
          'name': member.name,
          'role': member.role,
        }).select();
        final rows = response as List<dynamic>;
        if (rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map);
          member.id = row['id'] as int?;
        }
      } else if (member.id != null) {
        print('Updating member in Supabase: ${member.name}');
        await client.from('flat_members').update({
          'name': member.name,
          'role': member.role,
        }).eq('id', member.id!);
      }
      _setSupabaseStatus('Member synced to Supabase', connected: true);
    } catch (error) {
      print('Failed to sync member to Supabase: $error');
      _setSupabaseStatus('Member sync failed: $error', connected: false);
    }
  }

  Future<void> _showAddTaskDialog() async {
    final titleController = TextEditingController();
    String category = 'Cleaning';
    String priority = 'Medium';
    String? assignedTo = widget.members.isNotEmpty ? widget.members.first.name : null;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add a task'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Task title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['Cleaning', 'Shopping', 'Bills', 'Laundry', 'Study']
                            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => category = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['Low', 'Medium', 'High']
                            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => priority = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: assignedTo,
                        decoration: const InputDecoration(
                          labelText: 'Assign to',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.members
                            .map((member) => DropdownMenuItem(value: member.name, child: Text(member.name)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => assignedTo = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  return;
                }

                final task = Task(
                  title: title,
                  category: category,
                  priority: priority,
                  assignedTo: assignedTo,
                );

                final recipient = assignedTo;
                if (recipient != null && recipient != 'Admin') {
                  widget.onAssignTask(recipient, title);
                }

                setState(() {
                  widget.tasks.add(task);
                });
                await _syncTask(task, isNew: true);
                if (!mounted) return;
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Save task'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleTask(Task task) async {
    setState(() {
      task.completed = !task.completed;
      if (!task.completed) {
        task.status = 'Planned';
      } else {
        task.status = 'Completed';
      }
    });
    await _syncTask(task, isNew: false);
  }

  Future<void> _updateTaskStatus(Task task, String status) async {
    setState(() {
      task.status = status;
      task.completed = status == 'Completed';
    });
    await _syncTask(task, isNew: false);
  }

  Future<void> _showUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create roommate account'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();
                if (username.isEmpty || password.isEmpty) {
                  return;
                }
                widget.onCreateUser(username, password);
                Navigator.of(context).pop();
              },
              child: const Text('Create user'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMemberDialog() async {
    final nameController = TextEditingController();
    final roleController = TextEditingController(text: 'Roommate');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add flat member'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Member name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roleController,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final role = roleController.text.trim();
                if (name.isEmpty || role.isEmpty) {
                  return;
                }
                final member = FlatMember(name: name, role: role);
                setState(() {
                  widget.members.add(member);
                });
                await _syncMember(member, isNew: true);
                if (!mounted) return;
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Add member'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Flat Manager', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      drawer: _buildAdminDrawer(theme),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [Colors.teal.shade600, Colors.teal.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.shade200.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${widget.currentUser.username.capitalize()}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Manage tasks, rent, and expenses for your flat with confidence.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_selectedAdminTab == 'Dashboard')
              _buildDashboardContent(theme)
            else if (_selectedAdminTab == 'Chat')
              _buildChatContent(theme)
            else if (_selectedAdminTab == 'Rent Collection')
              _buildRentCollectionContent(theme)
            else if (_selectedAdminTab == 'Monthly Expenses')
              _buildMonthlyExpensesContent(theme)
            else
              _buildUserManagementContent(theme),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
    );
  }

  Widget _buildAdminDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade700, Colors.teal.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Text(
                'Flat Control',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...[
              _buildDrawerOption(theme, Icons.dashboard_outlined, 'Dashboard', 'Dashboard'),
              _buildDrawerOption(theme, Icons.people_outline, 'Roommates', 'User Management'),
              _buildDrawerOption(theme, Icons.chat_bubble_outline, 'Chat', 'Chat'),
              _buildDrawerOption(theme, Icons.attach_money, 'Rent', 'Rent Collection'),
              _buildDrawerOption(theme, Icons.receipt_long_outlined, 'Expenses', 'Monthly Expenses'),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Navigate to manage tasks, rent sharing, and monthly costs with a clean workspace.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ),
            Center(
              child: Text(
                'Copyright © 2026 Tushar Narkhede. All rights reserved.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black38),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerOption(ThemeData theme, IconData icon, String label, String tabName) {
    final selected = _selectedAdminTab == tabName;
    return ListTile(
      leading: Icon(icon, color: selected ? theme.colorScheme.primary : Colors.black54),
      title: Text(label, style: TextStyle(color: selected ? theme.colorScheme.primary : Colors.black87)),
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: () {
        setState(() => _selectedAdminTab = tabName);
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildChatContent(ThemeData theme) {
    final roommates = widget.users.where((user) => user.role == 'roommate').toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Chat', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'Chat with roommates directly from the admin panel.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (roommates.isEmpty)
              Text('No roommates are available for chat.', style: theme.textTheme.bodyMedium)
            else
              ...roommates.map((user) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.username.capitalize(),
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => widget.onOpenChat(context, user.username),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Chat'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                title: 'Pending',
                value: _pendingCount.toString(),
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                title: 'Done',
                value: _doneCount.toString(),
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: ['All', 'Pending', 'Done'].map((filter) {
            final selected = _selectedFilter == filter;
            return ChoiceChip(
              label: Text(filter),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedFilter = filter);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Text(
          widget.debugSummary,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        if (_visibleTasks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No tasks here yet. Add one to get started.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          )
        else
          ..._visibleTasks.map((task) => _buildTaskTile(task, theme)),
      ],
    );
  }

  Widget _buildUserManagementContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _showUserDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add user'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _showMemberDialog,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Add member'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildUsersView(theme),
        const SizedBox(height: 16),
        _buildMembersSection(theme),
      ],
    );
  }

  Widget _buildRentCollectionContent(ThemeData theme) {
    final roommateMembers = widget.members.where((member) => member.name != 'Admin').toList();
    final splitAmount = _currentSplitAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly rent collection',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a month, choose roommates, and split the rent fairly.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRentMonth.isEmpty ? null : _selectedRentMonth,
                  decoration: const InputDecoration(
                    labelText: 'Month',
                    border: OutlineInputBorder(),
                  ),
                  items: _buildMonthOptions().map((month) {
                    return DropdownMenuItem<String>(
                      value: month,
                      child: Text(month),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedRentMonth = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _totalRentController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Total rent for this month',
                    border: OutlineInputBorder(),
                    prefixText: '₹',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        title: 'Selected roommates',
                        value: '${_selectedRentMembers.length}',
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        context,
                        title: 'Split each',
                        value: '₹${splitAmount.toStringAsFixed(0)}',
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly total summary',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                context,
                                title: 'Rent',
                                value: '₹${double.tryParse(_totalRentController.text) ?? 0}',
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                context,
                                title: 'Expenses',
                                value: '₹${_monthlyExpensesTotal.toStringAsFixed(0)}',
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildStatCard(
                          context,
                          title: 'Total shared cost',
                          value: '₹${_sharedCostTotal.toStringAsFixed(0)}',
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _applyEqualSplit,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Apply equal split'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _saveRentEntry,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save for this month'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (roommateMembers.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Add flat members to start rent collection.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select roommates and distribute',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                       columns: const [
                         DataColumn(label: Text('Select')),
                         DataColumn(label: Text('Roommate')),
                         DataColumn(label: Text('Amount')),
                         DataColumn(label: Text('Actions')),
                       ],
                      rows: roommateMembers.map((member) {
                        final isSelected = _selectedRentMembers.contains(member.name);
                        final valueText = _rentValuesByMember[member.name] ?? splitAmount.toStringAsFixed(0);
                        _ensureRentController(member.name, valueText);
                        final fieldController = _rentControllersByMember[member.name]!;

                        return DataRow(
                          selected: isSelected,
                          onSelectChanged: (selected) {
                            setState(() {
                              if (selected ?? false) {
                                if (!_selectedRentMembers.contains(member.name)) {
                                  _selectedRentMembers.add(member.name);
                                }
                                _ensureRentController(member.name, splitAmount.toStringAsFixed(0));
                                _rentValuesByMember[member.name] = splitAmount.toStringAsFixed(0);
                              } else {
                                _selectedRentMembers.remove(member.name);
                                final controller = _rentControllersByMember.remove(member.name);
                                controller?.dispose();
                                _rentValuesByMember.remove(member.name);
                              }
                            });
                          },
                          cells: [
                            DataCell(
                              Checkbox(
                                value: isSelected,
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected ?? false) {
                                      if (!_selectedRentMembers.contains(member.name)) {
                                        _selectedRentMembers.add(member.name);
                                      }
                                      _ensureRentController(member.name, splitAmount.toStringAsFixed(0));
                                      _rentValuesByMember[member.name] = splitAmount.toStringAsFixed(0);
                                    } else {
                                      _selectedRentMembers.remove(member.name);
                                      final controller = _rentControllersByMember.remove(member.name);
                                      controller?.dispose();
                                      _rentValuesByMember.remove(member.name);
                                    }
                                  });
                                },
                              ),
                            ),
                            DataCell(Text(member.name)),
                            DataCell(
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: fieldController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixText: '₹',
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _rentValuesByMember[member.name] = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                             DataCell(
                               Row(
                                 mainAxisSize: MainAxisSize.min,
                                 children: [
                                   FilledButton(
                                     onPressed: () {
                                       setState(() {
                                         final selectedMembers = _selectedRentMembers.isEmpty
                                             ? <String>[member.name]
                                             : _selectedRentMembers.toList();
                                         if (!_selectedRentMembers.contains(member.name)) {
                                           _selectedRentMembers.add(member.name);
                                         }
                                         final shareValue = _sharedCostTotal / selectedMembers.length;
                                         final shareText = shareValue.toStringAsFixed(0);
                                         for (final selectedName in selectedMembers) {
                                           _ensureRentController(selectedName, shareText);
                                           _rentControllersByMember[selectedName]!.text = shareText;
                                           _rentValuesByMember[selectedName] = shareText;
                                         }
                                         _distributedMembers.add(member.name);
                                       });
                                     },
                                     style: FilledButton.styleFrom(
                                       backgroundColor: _distributedMembers.contains(member.name)
                                           ? Colors.green
                                           : Colors.red,
                                       foregroundColor: Colors.white,
                                     ),
                                     child: const Text('Distribute'),
                                   ),
                                   const SizedBox(width: 8),
                                   FilledButton(
                                     onPressed: () {
                                       setState(() {
                                         _receivedMembers.add(member.name);
                                       });
                                     },
                                     style: FilledButton.styleFrom(
                                       backgroundColor: _receivedMembers.contains(member.name)
                                           ? Colors.green
                                           : Colors.red,
                                       foregroundColor: Colors.white,
                                     ),
                                     child: const Text('Received'),
                                   ),
                                 ],
                               ),
                              ),
                           ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_savedRentEntries.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved rent entries',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ..._savedRentEntries.reversed.map((entry) {
                      final amountsText = entry.memberAmounts.entries.map((pair) => '${pair.key}: ₹${pair.value}').join(' • ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry.monthLabel} • Total ₹${entry.totalRent.toStringAsFixed(0)}',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(amountsText, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildMonthlyExpensesContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly expenses',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a month, add shared expenses, and include them in the roommate split.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedExpenseMonth.isEmpty ? null : _selectedExpenseMonth,
                  decoration: const InputDecoration(
                    labelText: 'Month',
                    border: OutlineInputBorder(),
                  ),
                  items: _buildMonthOptions().map((month) {
                    return DropdownMenuItem<String>(value: month, child: Text(month));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedExpenseMonth = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedExpenseCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Gas', 'Shopping', 'Light Bill', 'Internet', 'Cleaning', 'Other']
                      .map((value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedExpenseCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _expenseTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Expense name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _expenseAmountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    prefixText: '₹',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saveMonthlyExpense,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add expense'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expenses summary',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        title: 'Total expenses',
                        value: '₹${_monthlyExpensesTotal.toStringAsFixed(0)}',
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        context,
                        title: 'Shared total',
                        value: '₹${_sharedCostTotal.toStringAsFixed(0)}',
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_monthlyExpenseEntries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No monthly expenses added yet.', style: theme.textTheme.bodyLarge),
            ),
          )
        else
          ..._monthlyExpenseEntries.reversed.where((entry) => !entry.deleted).map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Text(entry.category[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${entry.category} • ${entry.monthLabel}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${entry.amount.toStringAsFixed(0)}', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                        IconButton(
                          onPressed: () => _removeMonthlyExpense(entry),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove expense',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildUsersView(ThemeData theme) {
    final roommates = widget.users.where((user) => user.role == 'roommate').toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Created users', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (roommates.isEmpty)
              Text('No roommate users created yet.', style: theme.textTheme.bodyMedium)
            else
              ...roommates.map((user) {
                final assignedTasks = widget.tasks.where((task) => task.assignedTo?.toLowerCase() == user.username.toLowerCase()).toList();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(user.username[0].toUpperCase()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.username.capitalize(), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                                Text('Password: ${user.password}', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => widget.onOpenChat(context, user.username),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text('Chat with ${user.username.capitalize()}'),
                      ),
                      const SizedBox(height: 12),
                      Text('Assigned tasks', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      if (assignedTasks.isEmpty)
                        Text('No tasks assigned yet.', style: theme.textTheme.bodyMedium)
                      else
                        ...assignedTasks.map((task) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Planned'),
                                      selected: task.status == 'Planned',
                                      onSelected: (_) => _updateTaskStatus(task, 'Planned'),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Started'),
                                      selected: task.status == 'Started',
                                      onSelected: (_) => _updateTaskStatus(task, 'Started'),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Completed'),
                                      selected: task.status == 'Completed',
                                      onSelected: (_) => _updateTaskStatus(task, 'Completed'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Flat members',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _showMemberDialog,
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Add member',
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...widget.members.map((member) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(member.name[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                            Text(member.role, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    if (member.name != 'Admin')
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove member',
                          onPressed: () {
                            setState(() {
                              widget.members.remove(member);
                            });
                          },
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(Task task, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: task.completed,
              onChanged: (_) => _toggleTask(task),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: task.completed ? TextDecoration.lineThrough : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${task.category} • ${task.priority} priority'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(task.category),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.secondaryContainer,
                      ),
                      if (task.assignedTo != null)
                        Chip(
                          label: Text(task.assignedTo!),
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        label: Text(task.status),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: task.status == 'Completed'
                            ? Colors.green.shade100
                            : task.status == 'Started'
                                ? Colors.orange.shade100
                                : Colors.blue.shade100,
                      ),
                      if (task.imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  child: InteractiveViewer(
                                    child: Image.network(task.imageUrl!, fit: BoxFit.contain),
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                task.imageUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.broken_image, size: 40);
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoommateHome extends StatefulWidget {
  const RoommateHome({
    super.key,
    required this.currentUser,
    required this.onLogout,
    required this.tasks,
    required this.members,
    required this.notifications,
    required this.rentEntries,
    required this.chatMessages,
    required this.onOpenChat,
    required this.onTaskImageUpdated,
  });

  final UserAccount currentUser;
  final VoidCallback onLogout;
  final List<Task> tasks;
  final List<FlatMember> members;
  final List<AppNotification> notifications;
  final List<RoommateRentEntry> rentEntries;
  final List<ChatMessage> chatMessages;
  final void Function(BuildContext context, String peerUsername) onOpenChat;
  final Future<String?> Function(Task task, XFile imageFile) onTaskImageUpdated;

  @override
  State<RoommateHome> createState() => _RoommateHomeState();
}

class _RoommateHomeState extends State<RoommateHome> {
  List<Task> get _assignedTasks {
    final username = widget.currentUser.username.toLowerCase();
    return widget.tasks.where((task) {
      final assignedTo = task.assignedTo?.toLowerCase();
      return assignedTo != null && assignedTo == username;
    }).toList();
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  List<RoommateRentEntry> get _tenantRentEntries {
    final username = widget.currentUser.username.toLowerCase();
    return widget.rentEntries.where((entry) => entry.username.toLowerCase() == username).toList();
  }

  double get _tenantTotalRent {
    return _tenantRentEntries.fold<double>(0, (sum, entry) => sum + entry.rent);
  }

  double get _tenantTotalExpenses {
    return _tenantRentEntries.fold<double>(0, (sum, entry) => sum + entry.expenses);
  }

  double get _tenantTotalAmount {
    return _tenantRentEntries.fold<double>(0, (sum, entry) => sum + entry.totalAmount);
  }

  void _updateTaskStatus(Task task, String status) {
    setState(() {
      task.status = status;
      task.completed = status == 'Completed';
    });
  }

  Future<void> _pickTaskImage(Task task) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (picked == null) {
      return;
    }

    final error = await widget.onTaskImageUpdated(task, picked);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your tasks'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your assigned tasks',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hello ${widget.currentUser.username.capitalize()}, here are the tasks assigned to you.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chat with admin',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => widget.onOpenChat(context, 'admin'),
                      icon: const Icon(Icons.chat),
                      label: const Text('Open chat'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.notifications.any((notification) {
              return !notification.isRead && notification.recipientUsername.toLowerCase() == widget.currentUser.username.toLowerCase();
            }))
              Card(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New notifications',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...widget.notifications.where((notification) {
                        return !notification.isRead && notification.recipientUsername.toLowerCase() == widget.currentUser.username.toLowerCase();
                      }).map((notification) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(notification.message)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your monthly rent summary',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Below are your monthly rent and expense totals calculated from admin distribution.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            context,
                            title: 'Rent',
                            value: '₹${_tenantTotalRent.toStringAsFixed(0)}',
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            context,
                            title: 'Expenses',
                            value: '₹${_tenantTotalExpenses.toStringAsFixed(0)}',
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      context,
                      title: 'Your total',
                      value: '₹${_tenantTotalAmount.toStringAsFixed(0)}',
                      color: Colors.indigo,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_tenantRentEntries.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rent entries',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ..._tenantRentEntries.reversed.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${entry.monthLabel} • total share ₹${entry.totalAmount.toStringAsFixed(0)}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              ),
                              Text('Rent: ₹${entry.rent.toStringAsFixed(0)}', style: theme.textTheme.bodySmall),
                              const SizedBox(width: 12),
                              Text('Exp: ₹${entry.expenses.toStringAsFixed(0)}', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (_assignedTasks.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No tasks assigned to you yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              )
            else
              ..._assignedTasks.map((task) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (task.status != 'Completed')
                              FilledButton.tonal(
                                onPressed: () => _updateTaskStatus(task, 'Started'),
                                child: const Text('Pick up'),
                              ),
                            if (task.status == 'Completed')
                              IconButton(
                                icon: Icon(
                                  task.imageUrl != null ? Icons.check_circle : Icons.image_outlined,
                                  color: task.imageUrl != null ? Colors.green : theme.colorScheme.primary,
                                ),
                                tooltip: task.imageUrl != null ? 'Image attached' : 'Attach completion image',
                                onPressed: () => _pickTaskImage(task),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${task.category} • ${task.priority} priority'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Planned'),
                              selected: task.status == 'Planned',
                              onSelected: (_) => _updateTaskStatus(task, 'Planned'),
                            ),
                            ChoiceChip(
                              label: const Text('Started'),
                              selected: task.status == 'Started',
                              onSelected: (_) => _updateTaskStatus(task, 'Started'),
                            ),
                            ChoiceChip(
                              label: const Text('Completed'),
                              selected: task.status == 'Completed',
                              onSelected: (_) => _updateTaskStatus(task, 'Completed'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.currentUser,
    required this.peerUsername,
    required this.initialMessages,
    required this.chatMessagesNotifier,
    required this.onSendMessage,
    required this.onChatOpened,
  });

  final UserAccount currentUser;
  final String peerUsername;
  final List<ChatMessage> initialMessages;
  final ValueNotifier<List<ChatMessage>> chatMessagesNotifier;
  final Future<String?> Function(String content, {XFile? imageFile}) onSendMessage;
  final Future<void> Function() onChatOpened;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  late List<ChatMessage> _messages;
  late final VoidCallback _notifierListener;

  @override
  void initState() {
    super.initState();
    _messages = List<ChatMessage>.from(widget.initialMessages);
    widget.onChatOpened();
    _notifierListener = () {
      setState(() {
        _messages = widget.chatMessagesNotifier.value
            .where((message) {
              final sender = message.senderUsername.toLowerCase();
              final recipient = message.recipientUsername.toLowerCase();
              final current = widget.currentUser.username.toLowerCase();
              final peer = widget.peerUsername.toLowerCase();
              return (sender == current && recipient == peer) ||
                  (sender == peer && recipient == current);
            })
            .toList();
      });
    };
    widget.chatMessagesNotifier.addListener(_notifierListener);
  }

  @override
  void dispose() {
    widget.chatMessagesNotifier.removeListener(_notifierListener);
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({XFile? imageFile}) async {
    final content = _messageController.text.trim();
    if (content.isEmpty && imageFile == null) {
      return;
    }

    final error = await widget.onSendMessage(content, imageFile: imageFile);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
    setState(() {
      _messages.add(ChatMessage(
        senderUsername: widget.currentUser.username,
        recipientUsername: widget.peerUsername,
        content: content,
        imageUrl: imageFile != null ? 'local://${imageFile.path}' : null,
        createdAt: DateTime.now().toUtc(),
      ));
      _messageController.clear();
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (picked != null) {
      await _sendMessage(imageFile: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.peerUsername.capitalize()}'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isMe = message.senderUsername.toLowerCase() == widget.currentUser.username.toLowerCase();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.content.isNotEmpty)
                              Text(
                                message.content,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                ),
                              ),
                            if (message.imageUrl != null) ...[
                              if (message.content.isNotEmpty) const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  message.imageUrl!,
                                  width: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Text(
                                      'Image unavailable',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                      ),
                                    );
                                  },
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const SizedBox(
                                      width: 220,
                                      height: 150,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${message.senderUsername.capitalize()} · ${_formatTime(message.createdAt)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isMe ? theme.colorScheme.onPrimary.withValues(alpha: 0.75) : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                       onSubmitted: (_) => _sendMessage(),
                     ),
                   ),
                   IconButton(
                     icon: const Icon(Icons.image_outlined),
                     tooltip: 'Send image',
                     onPressed: _pickImage,
                   ),
                   const SizedBox(width: 4),
                   FilledButton(
                     onPressed: () => _sendMessage(),
                     child: const Icon(Icons.send),
                   ),
                ],
              ),
            ),
            ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return this;
    }
    return this[0].toUpperCase() + substring(1);
  }
}
