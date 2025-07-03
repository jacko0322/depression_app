import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(DepressionApp());
}

class DepressionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心靈陪伴',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 驗證包裝器 - 檢查用戶登入狀態
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SplashScreen();
        }

        if (snapshot.hasData) {
          return MainHomePage();
        } else {
          return LoginPage();
        }
      },
    );
  }
}

// 啟動頁面
class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite, size: 100, color: Colors.blue[300]),
            SizedBox(height: 20),
            Text(
              '心靈陪伴',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 10),
            Text(
              '關愛自己，從心開始',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 30),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
            ),
          ],
        ),
      ),
    );
  }
}

// 登入註冊頁面
class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.psychology, size: 80, color: Colors.blue[400]),
              SizedBox(height: 30),
              Text(
                _isLogin ? '歡迎回來' : '建立帳戶',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              SizedBox(height: 40),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '電子郵件',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密碼',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleAuth,
                child: _isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text(_isLogin ? '登入' : '註冊'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[400],
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(
                  _isLogin ? '還沒有帳戶？立即註冊' : '已有帳戶？立即登入',
                  style: TextStyle(color: Colors.blue[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('請填寫所有欄位');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // 建立用戶資料
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'email': _emailController.text.trim(),
          'role': '個人使用者',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _showMessage(_getErrorMessage(e.toString()));
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getErrorMessage(String error) {
    if (error.contains('user-not-found')) return '找不到此用戶';
    if (error.contains('wrong-password')) return '密碼錯誤';
    if (error.contains('email-already-in-use')) return '此電子郵件已被使用';
    if (error.contains('weak-password')) return '密碼強度不足';
    if (error.contains('invalid-email')) return '電子郵件格式錯誤';
    return '發生錯誤，請稍後再試';
  }
}

// 主頁面
class MainHomePage extends StatefulWidget {
  @override
  _MainHomePageState createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    DailyTasksPage(),
    MoodRecordPage(),
    RelaxationPage(),
    EducationPage(),
    CharacterPage(),
    WateringGamePage(), // 新增澆水任務頁面
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('心靈陪伴'),
        backgroundColor: Colors.blue[400],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue[600],
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 10,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: '每日任務'),
          BottomNavigationBarItem(icon: Icon(Icons.mood), label: '心情記錄'),
          BottomNavigationBarItem(icon: Icon(Icons.spa), label: '舒緩心理'),
          BottomNavigationBarItem(icon: Icon(Icons.school), label: '資源教育'),
          BottomNavigationBarItem(icon: Icon(Icons.pets), label: '角色培養'),
          BottomNavigationBarItem(icon: Icon(Icons.eco), label: '澆水任務'),
        ],
      ),
    );
  }
}

// 每日任務頁面
class DailyTasksPage extends StatefulWidget {
  @override
  _DailyTasksPageState createState() => _DailyTasksPageState();
}

class _DailyTasksPageState extends State<DailyTasksPage> {
  final List<Map<String, dynamic>> _tasks = [
    {'title': '喝足夠的水', 'subtitle': '8杯水', 'icon': Icons.local_drink, 'color': Colors.blue},
    {'title': '運動10分鐘', 'subtitle': '簡單伸展', 'icon': Icons.fitness_center, 'color': Colors.green},
    {'title': '冥想5分鐘', 'subtitle': '放鬆心情', 'icon': Icons.self_improvement, 'color': Colors.purple},
    {'title': '寫心情日記', 'subtitle': '記錄感受', 'icon': Icons.edit, 'color': Colors.orange},
  ];

  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Center(child: Text('請先登入'));

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日任務',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<Map<String, bool>>(
              stream: _getTodayTasksCompletion(userId),
              builder: (context, snapshot) {
                Map<String, bool> completions = snapshot.data ?? {};

                return ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    var task = _tasks[index];
                    bool isCompleted = completions[task['title']] ?? false;

                    return Card(
                      margin: EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: task['color'][400],
                          child: Icon(task['icon'], color: Colors.white),
                        ),
                        title: Text(task['title']),
                        subtitle: Text(task['subtitle']),
                        trailing: Checkbox(
                          value: isCompleted,
                          onChanged: (value) {
                            _updateTaskCompletion(task['title'], value ?? false);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<Map<String, bool>> _getTodayTasksCompletion(String userId) {
    String today = DateTime.now().toIso8601String().split('T')[0];

    return FirebaseFirestore.instance
        .collection('daily_tasks')
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: today)
        .snapshots()
        .map((snapshot) {
      Map<String, bool> completions = {};
      for (var doc in snapshot.docs) {
        completions[doc.data()['taskTitle']] = doc.data()['isCompleted'] ?? false;
      }
      return completions;
    });
  }

  Future<void> _updateTaskCompletion(String taskTitle, bool isCompleted) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    String today = DateTime.now().toIso8601String().split('T')[0];
    String docId = '${userId}_${today}_${taskTitle.replaceAll(' ', '_')}';

    await FirebaseFirestore.instance.collection('daily_tasks').doc(docId).set({
      'userId': userId,
      'taskTitle': taskTitle,
      'isCompleted': isCompleted,
      'date': today,
      'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
    }, SetOptions(merge: true));
  }
}

// 心情記錄頁面
class MoodRecordPage extends StatefulWidget {
  @override
  _MoodRecordPageState createState() => _MoodRecordPageState();
}

class _MoodRecordPageState extends State<MoodRecordPage> {
  final TextEditingController _descriptionController = TextEditingController();
  int _selectedMood = -1;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _moods = [
    {'emoji': '😊', 'label': '開心', 'value': 0},
    {'emoji': '😐', 'label': '普通', 'value': 1},
    {'emoji': '😔', 'label': '難過', 'value': 2},
    {'emoji': '😢', 'label': '痛苦', 'value': 3},
  ];

  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Center(child: Text('請先登入'));

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '心情記錄',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 20),
          Text('今天的心情如何？', style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _moods.map((mood) {
              return _buildMoodButton(mood['emoji'], mood['label'], mood['value']);
            }).toList(),
          ),
          SizedBox(height: 30),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '今天發生了什麼？',
              border: OutlineInputBorder(),
              hintText: '記錄你的感受和想法...',
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveMoodRecord,
            child: _isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : Text('儲存記錄'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[400],
              foregroundColor: Colors.white,
              minimumSize: Size(double.infinity, 50),
            ),
          ),
          SizedBox(height: 30),
          Text(
            '最近的記錄',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Expanded(child: _buildMoodHistory(userId)),
        ],
      ),
    );
  }

  Widget _buildMoodButton(String emoji, String label, int value) {
    bool isSelected = _selectedMood == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMood = value;
        });
      },
      child: Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[100] : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blue[400]! : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: TextStyle(fontSize: 24)),
            SizedBox(height: 5),
            Text(label, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodHistory(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mood_records')
          .where('userId', isEqualTo: userId)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('載入錯誤: ${snapshot.error}'));
        }

        var records = snapshot.data?.docs ?? [];

        if (records.isEmpty) {
          return Center(child: Text('還沒有記錄'));
        }

        return ListView.builder(
          itemCount: records.length,
          itemBuilder: (context, index) {
            var record = records[index].data() as Map<String, dynamic>;
            var mood = _moods[record['moodLevel'] ?? 0];

            return Card(
              margin: EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Text(mood['emoji'], style: TextStyle(fontSize: 24)),
                title: Text(mood['label']),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record['description'] ?? ''),
                    SizedBox(height: 5),
                    Text(
                      _formatDate(record['recordedAt']?.toDate() ?? DateTime.now()),
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveMoodRecord() async {
    if (_selectedMood == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請選擇心情')),
      );
      return;
    }

    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance.collection('mood_records').add({
        'userId': userId,
        'moodLevel': _selectedMood,
        'description': _descriptionController.text,
        'recordedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記錄已儲存')),
      );

      setState(() {
        _selectedMood = -1;
        _descriptionController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗: $e')),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// 舒緩心理頁面 - 整合壓力抒發遊戲
class RelaxationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '舒緩心理',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 20),
          Text(
            '選擇一個活動來放鬆心情 🌱',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _buildRelaxationCard(
                  context,
                  '戳泡泡紙',
                  '🎈',
                  '釋放壓力的最佳方式',
                  Colors.blue,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PopItPage()),
                  ),
                ),
                _buildRelaxationCard(
                  context,
                  '呼吸冥想',
                  '🌱',
                  '跟著節奏深呼吸',
                  Colors.green,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BreathingPage()),
                  ),
                ),
                _buildRelaxationCard(
                  context,
                  '情緒釋放',
                  '🗑️',
                  '寫下煩惱然後丟掉',
                  Colors.orange,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EmotionReleasePage()),
                  ),
                ),
                _buildRelaxationCard(
                  context,
                  '療癒語錄',
                  '✨',
                  '每日正能量句子',
                  Colors.purple,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HealingQuotePage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelaxationCard(
      BuildContext context,
      String title,
      String emoji,
      String subtitle,
      Color color,
      VoidCallback onTap,
      ) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.7), color],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: TextStyle(fontSize: 32)),
              SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 1. 戳泡泡紙遊戲
class PopItPage extends StatefulWidget {
  @override
  State<PopItPage> createState() => _PopItPageState();
}

class _PopItPageState extends State<PopItPage> with TickerProviderStateMixin {
  List<bool> popped = List.generate(42, (index) => false);
  int poppedCount = 0;
  late AnimationController _celebrationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );
  }

  void _popBubble(int index) {
    if (popped[index]) return;

    setState(() {
      popped[index] = true;
      poppedCount++;
    });

    // 全部戳完的慶祝
    if (poppedCount == popped.length) {
      _celebrationController.forward();
      _showCelebrationDialog();
    }
  }

  void _showCelebrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🎉 太棒了！'),
        content: Text('你已經戳完了所有泡泡！\n感覺是不是放鬆多了？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetGame();
            },
            child: Text('再來一次'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('返回'),
          ),
        ],
      ),
    );
  }

  void _resetGame() {
    setState(() {
      popped = List.generate(42, (index) => false);
      poppedCount = 0;
    });
    _celebrationController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('戳泡泡紙'),
        backgroundColor: Colors.blue[400],
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _resetGame, icon: Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.blue[50],
            child: Text(
              '已戳破：$poppedCount / ${popped.length}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: GridView.builder(
                padding: EdgeInsets.all(20),
                itemCount: popped.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _popBubble(index),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: popped[index] ? Colors.grey[300] : Colors.blue[200],
                        shape: BoxShape.circle,
                        boxShadow: popped[index]
                            ? []
                            : [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: popped[index]
                            ? Icon(Icons.check, color: Colors.grey, size: 20)
                            : Icon(Icons.circle, color: Colors.blue, size: 16),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }
}

// 2. 呼吸冥想遊戲
class BreathingPage extends StatefulWidget {
  @override
  State<BreathingPage> createState() => _BreathingPageState();
}

class _BreathingPageState extends State<BreathingPage> with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _colorController;
  late Animation<Color?> _colorAnimation;
  String breathText = "準備開始";
  String phaseText = "深呼吸放鬆";
  int seconds = 0;
  bool isActive = false;
  Timer? _timer;
  int totalMinutes = 0;

  final List<String> breathingModes = ['4-4-4 基礎', '4-7-8 深度', '6-6-6 平衡'];
  int currentMode = 0;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4),
    );
    _colorController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 8),
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: Colors.teal[300],
      end: Colors.blue[300],
    ).animate(_colorController);
  }

  void _startBreathing() {
    setState(() {
      isActive = true;
      seconds = 0;
    });

    _startBreathingCycle();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        seconds++;
        if (seconds % 60 == 0) totalMinutes++;
      });
    });
  }

  void _startBreathingCycle() {
    int inhale, hold, exhale;
    switch (currentMode) {
      case 0: // 4-4-4
        inhale = 4; hold = 4; exhale = 4;
        break;
      case 1: // 4-7-8
        inhale = 4; hold = 7; exhale = 8;
        break;
      case 2: // 6-6-6
        inhale = 6; hold = 6; exhale = 6;
        break;
      default:
        inhale = 4; hold = 4; exhale = 4;
    }
    _breathCycle(inhale, hold, exhale);
  }

  void _breathCycle(int inhale, int hold, int exhale) async {
    if (!isActive) return;

    // 吸氣
    setState(() {
      breathText = "吸氣";
      phaseText = "慢慢吸氣，感受空氣進入";
    });
    _breathController.forward(from: 0);
    await Future.delayed(Duration(seconds: inhale));

    if (!isActive) return;

    // 憋氣
    setState(() {
      breathText = "憋氣";
      phaseText = "保持呼吸，讓身體放鬆";
    });
    await Future.delayed(Duration(seconds: hold));

    if (!isActive) return;

    // 吐氣
    setState(() {
      breathText = "吐氣";
      phaseText = "慢慢吐氣，釋放壓力";
    });
    _breathController.reverse();
    await Future.delayed(Duration(seconds: exhale));

    // 重複循環
    _breathCycle(inhale, hold, exhale);
  }

  void _stopBreathing() {
    setState(() {
      isActive = false;
      breathText = "準備開始";
      phaseText = "深呼吸放鬆";
    });
    _timer?.cancel();
    _breathController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[50],
      appBar: AppBar(
        title: Text('呼吸冥想'),
        backgroundColor: Colors.teal[400],
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<int>(
            onSelected: (value) {
              setState(() {
                currentMode = value;
              });
              if (isActive) {
                _stopBreathing();
                _startBreathing();
              }
            },
            itemBuilder: (context) => breathingModes.asMap().entries.map((entry) {
              return PopupMenuItem(value: entry.key, child: Text(entry.value));
            }).toList(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${breathingModes[currentMode]} 呼吸法',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 20),
            Text(
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 40),
            AnimatedBuilder(
              animation: Listenable.merge([_breathController, _colorAnimation]),
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.5 + _breathController.value * 0.8,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: _colorAnimation.value,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _colorAnimation.value!.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        breathText,
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 40),
            Text(
              phaseText,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: isActive ? null : _startBreathing,
                  icon: Icon(Icons.play_arrow),
                  label: Text('開始'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[400],
                    foregroundColor: Colors.white,
                  ),
                ),
                SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: isActive ? _stopBreathing : null,
                  icon: Icon(Icons.stop),
                  label: Text('停止'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _breathController.dispose();
    _colorController.dispose();
    _timer?.cancel();
    super.dispose();
  }
}

// 3. 情緒釋放頁面
class EmotionReleasePage extends StatefulWidget {
  @override
  State<EmotionReleasePage> createState() => _EmotionReleasePageState();
}

class _EmotionReleasePageState extends State<EmotionReleasePage> with TickerProviderStateMixin {
  final TextEditingController _emotionController = TextEditingController();
  late AnimationController _deleteController;
  late Animation<double> _scaleAnimation;
  List<String> _savedEmotions = [];

  @override
  void initState() {
    super.initState();
    _deleteController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _deleteController, curve: Curves.easeInBack),
    );
  }

  void _releaseEmotion() {
    if (_emotionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請先寫下你的煩惱')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🗑️ 釋放情緒'),
        content: Text('你確定要丟掉這個煩惱嗎？\n\n"${_emotionController.text}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performRelease();
            },
            child: Text('丟掉它！'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _performRelease() {
    setState(() {
      _savedEmotions.insert(0, _emotionController.text);
    });

    _deleteController.forward().then((_) {
      _emotionController.clear();
      _deleteController.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('煩惱已經被丟掉了！感覺輕鬆多了 😌'),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('情緒釋放'),
        backgroundColor: Colors.orange[400],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '寫下你的煩惱 ✍️',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange[800],
              ),
            ),
            SizedBox(height: 10),
            Text(
              '把心中的負面情緒寫出來，然後象徵性地丟掉它們',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 30),
            ScaleTransition(
              scale: _scaleAnimation,
              child: TextField(
                controller: _emotionController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: '在這裡寫下讓你煩惱的事情...\n\n例如：今天工作壓力很大，感覺很累...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.orange[50],
                ),
              ),
            ),
            SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _releaseEmotion,
                icon: Icon(Icons.delete_outline),
                label: Text('丟掉煩惱'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[400],
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              ),
            ),
            SizedBox(height: 30),
            if (_savedEmotions.isNotEmpty) ...[
              Text(
                '已釋放的情緒 🌟',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _savedEmotions.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: EdgeInsets.only(bottom: 8),
                      color: Colors.grey[100],
                      child: ListTile(
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Text(
                          _savedEmotions[index],
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey[600],
                          ),
                        ),
                        subtitle: Text('已釋放'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deleteController.dispose();
    _emotionController.dispose();
    super.dispose();
  }
}

// 4. 療癒語錄頁面
class HealingQuotePage extends StatefulWidget {
  @override
  State<HealingQuotePage> createState() => _HealingQuotePageState();
}

class _HealingQuotePageState extends State<HealingQuotePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  int currentQuoteIndex = 0;

  final List<Map<String, String>> quotes = [
    {'quote': '每一個今天，都是餘生的第一天', 'author': '匿名'},
    {'quote': '你比你想像的更勇敢，比你看起來更強壯', 'author': '小熊維尼'},
    {'quote': '黑暗中，一點點光就足以照亮前路', 'author': '匿名'},
    {'quote': '治癒自己是一種超能力', 'author': '匿名'},
    {'quote': '每個結束都是新的開始', 'author': '匿名'},
    {'quote': '你的價值不取決於別人的認可', 'author': '匿名'},
    {'quote': '今天的雨是明天彩虹的開始', 'author': '匿名'},
    {'quote': '接受自己的不完美，是完美的開始', 'author': '匿名'},
    {'quote': '內心平靜比什麼都重要', 'author': '匿名'},
    {'quote': '小小的進步也是進步', 'author': '匿名'},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    currentQuoteIndex = Random().nextInt(quotes.length);
    _animationController.forward();
  }

  void _nextQuote() {
    _animationController.reverse().then((_) {
      setState(() {
        currentQuoteIndex = (currentQuoteIndex + 1) % quotes.length;
      });
      _animationController.forward();
    });
  }

  void _randomQuote() {
    _animationController.reverse().then((_) {
      setState(() {
        currentQuoteIndex = Random().nextInt(quotes.length);
      });
      _animationController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.purple[50],
      appBar: AppBar(
        title: Text('療癒語錄'),
        backgroundColor: Colors.purple[400],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _randomQuote,
            icon: Icon(Icons.shuffle),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.format_quote,
                  size: 60,
                  color: Colors.purple[300],
                ),
                SizedBox(height: 30),
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.purple[100]!, Colors.purple[200]!],
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          quotes[currentQuoteIndex]['quote']!,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.purple[800],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        Text(
                          '— ${quotes[currentQuoteIndex]['author']}',
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.purple[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _nextQuote,
                      icon: Icon(Icons.arrow_forward),
                      label: Text('下一句'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[400],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: _randomQuote,
                      icon: Icon(Icons.shuffle),
                      label: Text('隨機'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[300],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 30),
                Text(
                  '${currentQuoteIndex + 1} / ${quotes.length}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

// 資源教育頁面
class EducationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '資源教育',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 20),
          _buildEducationCard('認識憂鬱症', '了解憂鬱症的症狀和成因', Icons.psychology, Colors.blue),
          _buildEducationCard('情緒管理技巧', '學習有效的情緒調節方法', Icons.emoji_emotions, Colors.green),
          _buildEducationCard('睡眠健康', '改善睡眠品質的方法', Icons.bedtime, Colors.purple),
          _buildEducationCard('人際關係', '建立健康的人際互動', Icons.people, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildEducationCard(String title, String subtitle, IconData icon, MaterialColor color) {
    return Card(
      margin: EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color[400],
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.arrow_forward_ios),
        onTap: () {
          // 這裡可以實作具體的教育內容
        },
      ),
    );
  }
}

// 角色培養頁面
class CharacterPage extends StatefulWidget {
  @override
  _CharacterPageState createState() => _CharacterPageState();
}

class _CharacterPageState extends State<CharacterPage> {
  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Center(child: Text('請先登入'));

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '我的夥伴',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 30),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pets')
                .doc(userId)
                .snapshots(),
            builder: (context, snapshot) {
              Map<String, dynamic> petData = {};

              if (snapshot.hasData && snapshot.data!.exists) {
                petData = snapshot.data!.data() as Map<String, dynamic>;
              } else {
                // 預設寵物狀態
                petData = {
                  'name': '小花',
                  'level': 1,
                  'experience': 0,
                  'happiness': 50,
                };
              }

              return Column(
                children: [
                  CircleAvatar(
                    radius: 80,
                    backgroundColor: Colors.pink[100],
                    child: Icon(
                      Icons.pets,
                      size: 80,
                      color: Colors.pink[400],
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    petData['name'] ?? '小花',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Level ${petData['level'] ?? 1}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: (petData['experience'] ?? 0) / 100.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.pink[400]!),
                  ),
                  SizedBox(height: 10),
                  Text('經驗值: ${petData['experience'] ?? 0}/100'),
                  SizedBox(height: 20),
                  Text('快樂值: ${petData['happiness'] ?? 50}/100'),
                  SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (petData['happiness'] ?? 50) / 100.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[400]!),
                  ),
                  SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton('餵食', Icons.restaurant, Colors.orange, () {
                        _performPetAction('feed', petData);
                      }),
                      _buildActionButton('玩耍', Icons.sports_esports, Colors.green, () {
                        _performPetAction('play', petData);
                      }),
                      _buildActionButton('清潔', Icons.cleaning_services, Colors.blue, () {
                        _performPetAction('clean', petData);
                      }),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, MaterialColor color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: color[400],
            child: Icon(icon, color: Colors.white),
          ),
          SizedBox(height: 5),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _performPetAction(String action, Map<String, dynamic> currentData) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    int newExperience = (currentData['experience'] ?? 0) + 10;
    int newHappiness = (currentData['happiness'] ?? 50) + 5;
    int newLevel = currentData['level'] ?? 1;

    // 升級邏輯
    if (newExperience >= 100) {
      newLevel += 1;
      newExperience = 0;
    }

    // 快樂值上限
    if (newHappiness > 100) {
      newHappiness = 100;
    }

    Map<String, dynamic> updateData = {
      'name': currentData['name'] ?? '小花',
      'level': newLevel,
      'experience': newExperience,
      'happiness': newHappiness,
    };

    // 記錄最後操作時間
    switch (action) {
      case 'feed':
        updateData['lastFed'] = FieldValue.serverTimestamp();
        break;
      case 'play':
        updateData['lastPlayed'] = FieldValue.serverTimestamp();
        break;
      case 'clean':
        updateData['lastCleaned'] = FieldValue.serverTimestamp();
        break;
    }

    try {
      await FirebaseFirestore.instance
          .collection('pets')
          .doc(userId)
          .set(updateData, SetOptions(merge: true));

      String actionText = action == 'feed' ? '餵食' : action == 'play' ? '玩耍' : '清潔';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$actionText 完成！獲得經驗值 +10, 快樂值 +5')),
      );

      if (newLevel > (currentData['level'] ?? 1)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恭喜！寵物升級到 Level $newLevel！')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失敗: $e')),
      );
    }
  }
}

// ==================== 澆水任務整合開始 ====================

// 澆水任務主頁面
class WateringGamePage extends StatefulWidget {
  @override
  State<WateringGamePage> createState() => _WateringGamePageState();
}

class _WateringGamePageState extends State<WateringGamePage> with TickerProviderStateMixin {
  late AnimationController _treeAnimationController;
  late Animation<double> _treeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _treeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _treeScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _treeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _treeAnimationController.dispose();
    super.dispose();
  }

  Future<void> _completeTask(String taskName) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    String today = DateTime.now().toIso8601String().split('T')[0];
    String docId = '${userId}_${today}_${taskName.replaceAll(' ', '_')}';

    await FirebaseFirestore.instance.collection('watering_tasks').doc(docId).set({
      'userId': userId,
      'taskName': taskName,
      'isCompleted': true,
      'date': today,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 播放樹長大動畫
    _treeAnimationController.forward().then((_) {
      _treeAnimationController.reverse();
    });

    // 顯示完成提示
    _showTaskCompletedDialog(taskName);
  }

  void _showTaskCompletedDialog(String taskName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('🎉 任務完成！'),
          content: Text('你完成了「$taskName」任務！\n樹獲得了一次澆水 💧'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('繼續'),
            ),
          ],
        );
      },
    );
  }

  String _getTreeStage(int waterCount) {
    if (waterCount == 0) return '🌰 種子';
    if (waterCount < 5) return '🌱 幼苗';
    if (waterCount < 10) return '🌿 小樹';
    if (waterCount < 15) return '🌳 中樹';
    if (waterCount < 20) return '🌲 快成熟';
    return '🎄 成熟的大樹！';
  }

  Color _getBackgroundColor(int waterCount) {
    double progress = waterCount / 20.0;
    return Color.lerp(Colors.brown.shade50, Colors.green.shade50, progress)!;
  }

  Future<void> _resetGame() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    String today = DateTime.now().toIso8601String().split('T')[0];

    // 刪除今日所有任務記錄
    var batch = FirebaseFirestore.instance.batch();
    var taskDocs = await FirebaseFirestore.instance
        .collection('watering_tasks')
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: today)
        .get();

    for (var doc in taskDocs.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  void _openTaskDetail(String taskName) {
    Widget taskWidget;

    switch (taskName) {
      case '喝水 💧':
        taskWidget = DrinkingTask(onCompleted: () => _completeTask(taskName));
        break;
      case '運動 🏃‍♂️':
        taskWidget = ExerciseTask(onCompleted: () => _completeTask(taskName));
        break;
      case '冥想 🧘':
        taskWidget = MeditationTask(onCompleted: () => _completeTask(taskName));
        break;
      case '寫心情日記 📖':
        taskWidget = DiaryTask(onCompleted: () => _completeTask(taskName));
        break;
      default:
        return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (context) => taskWidget));
  }

  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Center(child: Text('請先登入'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('watering_tasks')
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: DateTime.now().toIso8601String().split('T')[0])
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, bool> completions = {};
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            completions[data['taskName']] = data['isCompleted'] ?? false;
          }
        }

        int waterCount = completions.values.where((completed) => completed).length;
        const int totalWater = 4; // 4個任務

        final List<Map<String, dynamic>> tasks = [
          {'name': '喝水 💧', 'subtitle': '8杯水目標'},
          {'name': '運動 🏃‍♂️', 'subtitle': '5分鐘運動'},
          {'name': '冥想 🧘', 'subtitle': '3分鐘冥想'},
          {'name': '寫心情日記 📖', 'subtitle': '記錄今日感受'},
        ];

        return Scaffold(
          backgroundColor: _getBackgroundColor(waterCount),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  '澆水養樹 🌱',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                SizedBox(height: 20),

                // 進度條
                Container(
                  width: double.infinity,
                  height: 15,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade300,
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: waterCount / totalWater,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [Colors.lightBlue, Colors.green.shade400],
                        ),
                      ),
                    ),
                  ),
                ),

                // 樹的狀態
                AnimatedBuilder(
                  animation: _treeScaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _treeScaleAnimation.value,
                      child: Text(
                        _getTreeStage(waterCount),
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 15),

                Text(
                  '目前已澆水：$waterCount / $totalWater 次',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),

                const SizedBox(height: 25),

                const Text(
                  '📋 完成每日任務來澆水：',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 15),

                // 任務列表
                Expanded(
                  child: ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      var task = tasks[index];
                      bool isCompleted = completions[task['name']] ?? false;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          title: Text(
                            task['name'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              decoration: isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isCompleted ? Colors.grey : Colors.black87,
                            ),
                          ),
                          subtitle: Text(task['subtitle']),
                          trailing: isCompleted
                              ? Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              color: Colors.green.shade700,
                              size: 20,
                            ),
                          )
                              : ElevatedButton(
                            onPressed: () => _openTaskDetail(task['name']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text('開始'),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 完成提示
                if (waterCount >= totalWater) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.yellow.shade100, Colors.orange.shade100],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '🎊 恭喜完成！ 🎊',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text('你成功讓樹長大了！', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 15),
                        ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('重置遊戲'),
                                  content: const Text('確定要重新開始嗎？這會清除所有進度。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _resetGame();
                                      },
                                      child: const Text('確定'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('重新開始'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// 任務狀態類別
class TaskStatus {
  bool isCompleted;

  TaskStatus({this.isCompleted = false});
}

// 喝水任務
class DrinkingTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const DrinkingTask({super.key, required this.onCompleted});

  @override
  State<DrinkingTask> createState() => _DrinkingTaskState();
}

class _DrinkingTaskState extends State<DrinkingTask> {
  int glasses = 0;
  final int targetGlasses = 8;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('喝水任務 💧'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.blue.shade50,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '今日喝水目標',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  '$glasses / $targetGlasses 杯',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                LinearProgressIndicator(
                  value: glasses / targetGlasses,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.blue,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: glasses < targetGlasses
                      ? () {
                    setState(() {
                      glasses++;
                      if (glasses >= targetGlasses) {
                        Future.delayed(
                          const Duration(milliseconds: 500),
                              () {
                            widget.onCompleted();
                            Navigator.of(context).pop();
                          },
                        );
                      }
                    });
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  child: const Text('喝一杯水 🥤', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 20),
                if (glasses >= targetGlasses)
                  const Text(
                    '🎉 太棒了！你完成了今日喝水目標！',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 運動任務
class ExerciseTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const ExerciseTask({super.key, required this.onCompleted});

  @override
  State<ExerciseTask> createState() => _ExerciseTaskState();
}

class _ExerciseTaskState extends State<ExerciseTask> {
  int seconds = 0;
  final int targetSeconds = 300; // 5分鐘
  bool isRunning = false;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (isRunning) {
      timer?.cancel();
    } else {
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          seconds++;
          if (seconds >= targetSeconds) {
            timer.cancel();
            isRunning = false;
            widget.onCompleted();
            Navigator.of(context).pop();
          }
        });
      });
    }
    setState(() {
      isRunning = !isRunning;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('運動任務 🏃‍♂️'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.orange.shade50,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '運動計時器',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  _formatTime(seconds),
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '目標：${_formatTime(targetSeconds)}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 30),
                LinearProgressIndicator(
                  value: seconds / targetSeconds,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.orange,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: seconds < targetSeconds ? _toggleTimer : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  child: Text(
                    isRunning ? '暫停 ⏸️' : '開始運動 ▶️',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 20),
                if (seconds >= targetSeconds)
                  const Text(
                    '🎉 太棒了！你完成了運動目標！',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 冥想任務
class MeditationTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const MeditationTask({super.key, required this.onCompleted});

  @override
  State<MeditationTask> createState() => _MeditationTaskState();
}

class _MeditationTaskState extends State<MeditationTask>
    with TickerProviderStateMixin {
  int seconds = 0;
  final int targetSeconds = 180; // 3分鐘
  bool isRunning = false;
  Timer? timer;
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _breatheAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    _breatheController.dispose();
    super.dispose();
  }

  void _toggleMeditation() {
    if (isRunning) {
      timer?.cancel();
      _breatheController.stop();
    } else {
      _breatheController.repeat(reverse: true);
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          seconds++;
          if (seconds >= targetSeconds) {
            timer.cancel();
            _breatheController.stop();
            isRunning = false;
            widget.onCompleted();
            Navigator.of(context).pop();
          }
        });
      });
    }
    setState(() {
      isRunning = !isRunning;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('冥想任務 🧘'),
        backgroundColor: Colors.purple.shade600,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.purple.shade50,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '冥想計時器',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                AnimatedBuilder(
                  animation: _breatheAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _breatheAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.purple.shade200,
                              Colors.purple.shade400,
                            ],
                          ),
                        ),
                        child: const Center(
                          child: Text('🧘', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                Text(
                  _formatTime(seconds),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '目標：${_formatTime(targetSeconds)}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 30),
                LinearProgressIndicator(
                  value: seconds / targetSeconds,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.purple,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: seconds < targetSeconds ? _toggleMeditation : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  child: Text(
                    isRunning ? '停止冥想 ⏸️' : '開始冥想 ▶️',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                if (isRunning) ...[
                  const SizedBox(height: 20),
                  const Text(
                    '深呼吸，跟著圓圈的節奏...',
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 20),
                if (seconds >= targetSeconds)
                  const Text(
                    '🎉 太棒了！你完成了冥想！',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 寫日記任務
class DiaryTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const DiaryTask({super.key, required this.onCompleted});

  @override
  State<DiaryTask> createState() => _DiaryTaskState();
}

class _DiaryTaskState extends State<DiaryTask> {
  final TextEditingController _diaryController = TextEditingController();
  final int minWords = 50;

  @override
  void dispose() {
    _diaryController.dispose();
    super.dispose();
  }

  int _getWordCount() {
    return _diaryController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
  }

  void _completeDiary() {
    if (_getWordCount() >= minWords) {
      widget.onCompleted();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('心情日記 📖'),
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.indigo.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天是 ${DateTime.now().month}/${DateTime.now().day}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '寫下你今天的心情和想法...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _diaryController,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                      '開始寫下你的心情...\n\n你今天過得怎麼樣？\n有什麼特別的事情發生嗎？\n你現在的感受是什麼？',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    onChanged: (text) {
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '字數：${_getWordCount()} / $minWords',
                    style: TextStyle(
                      fontSize: 16,
                      color: _getWordCount() >= minWords
                          ? Colors.green
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _getWordCount() >= minWords
                        ? _completeDiary
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('完成日記', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}