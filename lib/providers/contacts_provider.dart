import 'package:flutter/material.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/socket_service.dart';

class ContactsProvider extends ChangeNotifier {
  final ApiClient api;
  final SocketService socket;

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendRequests = [];
  bool _loading = false;
  int _pendingRequestCount = 0;

  ContactsProvider({required this.api, required this.socket}) {
    socket.on('friend:request-new', _onFriendRequestNew);
    socket.on('friend:added', _onFriendAdded);
    socket.on('friend:request-rejected', _onFriendRequestRejected);
  }

  List<Map<String, dynamic>> get friends => _friends;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  bool get loading => _loading;
  int get pendingRequestCount => _pendingRequestCount;

  Future<void> loadFriends() async {
    try {
      _loading = true;
      notifyListeners();
      final data = await api.get('/friends');
      _friends = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadFriendRequests() async {
    try {
      final data = await api.get('/friends/requests');
      _friendRequests = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> searchUsers(String keyword) async {
    final data = await api.get('/users/search', params: {'keyword': keyword});
    return List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);
  }

  Future<void> sendFriendRequest(int targetUserId, String message) async {
    await api.post('/friends/requests', data: {
      'targetUserId': targetUserId,
      'message': message,
    });
  }

  Future<void> handleFriendRequest(int requestId, String action) async {
    await api.put('/friends/requests/$requestId', data: {'action': action});
    await loadFriendRequests();
    await loadFriends();
  }

  Future<void> deleteFriend(int friendId) async {
    await api.delete('/friends/$friendId');
    await loadFriends();
  }

  Future<void> blockFriend(int friendId) async {
    await api.post('/friends/$friendId/block');
    await loadFriends();
  }

  Future<void> unblockFriend(int friendId) async {
    await api.delete('/friends/$friendId/block');
    await loadFriends();
  }

  Future<void> starFriend(int friendId) async {
    await api.post('/friends/$friendId/star');
    await loadFriends();
  }

  Future<void> unstarFriend(int friendId) async {
    await api.delete('/friends/$friendId/star');
    await loadFriends();
  }

  void _onFriendRequestNew(dynamic data) {
    // 收到新的好友申请，刷新好友申请列表
    _pendingRequestCount++;
    notifyListeners();
    loadFriendRequests();
  }

  void _onFriendAdded(dynamic data) {
    // 新好友添加成功，刷新好友列表
    _pendingRequestCount = 0;
    notifyListeners();
    loadFriends();
    loadFriendRequests();
  }

  void _onFriendRequestRejected(dynamic data) {
    // 好友申请被拒绝
    loadFriendRequests();
  }

  void clearPendingCount() {
    _pendingRequestCount = 0;
    notifyListeners();
  }
}
