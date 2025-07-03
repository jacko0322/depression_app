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
    IntegratedGrowthPage(), // 整合的成長頁面
    MoodRecordPage(),
    RelaxationPage(),
    EducationPage(),
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
          BottomNavigationBarItem(icon: Icon(Icons.eco), label: '成長花園'),
          BottomNavigationBarItem(icon: Icon(Icons.mood), label: '心情記錄'),
          BottomNavigationBarItem(icon: Icon(Icons.spa), label: '舒緩心理'),
          BottomNavigationBarItem(icon: Icon(Icons.school), label: '資源教育'),
        ],
      ),
    );
  }
}

// 整合的成長頁面（合併每日任務、角色培養、澆水任務）
class IntegratedGrowthPage extends StatefulWidget {
  @override
  _IntegratedGrowthPageState createState() => _IntegratedGrowthPageState();
}

class _IntegratedGrowthPageState extends State<IntegratedGrowthPage> with TickerProviderStateMixin {
  late AnimationController _celebrationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  Future<void> _completeTask(String taskTitle) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    String today = DateTime.now().toIso8601String().split('T')[0];
    String docId = '${userId}_${today}_${taskTitle.replaceAll(' ', '_')}';

    // 更新每日任務完成狀態
    await FirebaseFirestore.instance.collection('daily_tasks').doc(docId).set({
      'userId': userId,
      'taskTitle': taskTitle,
      'isCompleted': true,
      'date': today,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 更新寵物狀態
    await _updatePetStatus(userId);

    // 播放慶祝動畫
    _celebrationController.forward().then((_) {
      _celebrationController.reverse();
    });

    // 顯示完成提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('任務完成！🎉 寵物和樹都成長了！（經驗值+5，快樂值+3）'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _updatePetStatus(String userId) async {
    DocumentSnapshot petDoc = await FirebaseFirestore.instance.collection('pets').doc(userId).get();

    Map<String, dynamic> petData = {};
    if (petDoc.exists) {
      petData = petDoc.data() as Map<String, dynamic>;
    }

    int currentExp = petData['experience'] ?? 0;
    int currentHappiness = petData['happiness'] ?? 50;
    int currentLevel = petData['level'] ?? 1;

    int newExp = currentExp + 5;  // 降低經驗值獲取，更符合養成感覺
    int newHappiness = (currentHappiness + 3).clamp(0, 100);  // 降低快樂值獲取
    int newLevel = currentLevel;

    // 升級邏輯
    if (newExp >= 100) {
      newLevel += 1;
      newExp = 0;
    }

    await FirebaseFirestore.instance.collection('pets').doc(userId).set({
      'name': petData['name'] ?? '小花',
      'level': newLevel,
      'experience': newExp,
      'happiness': newHappiness,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _openTaskDetail(String taskTitle) {
    Widget taskWidget;

    switch (taskTitle) {
      case '喝足夠的水':
        taskWidget = DrinkingTask(onCompleted: () => _completeTask(taskTitle));
        break;
      case '運動10分鐘':
        taskWidget = ExerciseTask(onCompleted: () => _completeTask(taskTitle));
        break;
      case '冥想5分鐘':
        taskWidget = MeditationTask(onCompleted: () => _completeTask(taskTitle));
        break;
      case '感恩練習':
        taskWidget = GratitudeTask(onCompleted: () => _completeTask(taskTitle));
        break;
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => taskWidget),
    );
  }

  String _getTreeStage(int completedTasks) {
    if (completedTasks == 0) return '🌰';
    if (completedTasks == 1) return '🌱';
    if (completedTasks == 2) return '🌿';
    if (completedTasks == 3) return '🌳';
    return '🌲';
  }

  Color _getBackgroundColor(int completedTasks) {
    double progress = completedTasks / 4.0;
    return Color.lerp(Colors.brown.shade50, Colors.green.shade50, progress)!;
  }

  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Center(child: Text('請先登入'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('daily_tasks')
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: DateTime.now().toIso8601String().split('T')[0])
          .snapshots(),
      builder: (context, taskSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('pets')
              .doc(userId)
              .snapshots(),
          builder: (context, petSnapshot) {
            // 處理任務數據
            Map<String, bool> taskCompletions = {};
            if (taskSnapshot.hasData) {
              for (var doc in taskSnapshot.data!.docs) {
                var data = doc.data() as Map<String, dynamic>;
                taskCompletions[data['taskTitle']] = data['isCompleted'] ?? false;
              }
            }

            int completedTasksCount = taskCompletions.values.where((completed) => completed).length;

            // 處理寵物數據
            Map<String, dynamic> petData = {};
            if (petSnapshot.hasData && petSnapshot.data!.exists) {
              petData = petSnapshot.data!.data() as Map<String, dynamic>;
            } else {
              petData = {
                'name': '小花',
                'level': 1,
                'experience': 0,
                'happiness': 50,
              };
            }

            final List<Map<String, dynamic>> tasks = [
              {'title': '喝足夠的水', 'subtitle': '8杯水', 'icon': Icons.local_drink, 'color': Colors.blue},
              {'title': '運動10分鐘', 'subtitle': '簡單伸展', 'icon': Icons.fitness_center, 'color': Colors.green},
              {'title': '冥想5分鐘', 'subtitle': '放鬆心情', 'icon': Icons.self_improvement, 'color': Colors.purple},
              {'title': '感恩練習', 'subtitle': '記錄感恩的事', 'icon': Icons.favorite, 'color': Colors.pink},
            ];

            return Scaffold(
              backgroundColor: _getBackgroundColor(completedTasksCount),
              body: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    // 標題
                    Text(
                      '成長花園 🌱',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    SizedBox(height: 20),

                    // 寵物和樹的狀態區域
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // 寵物區域
                              Column(
                                children: [
                                  Text('我的夥伴', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 10),
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundColor: Colors.pink[100],
                                    child: Icon(Icons.pets, size: 40, color: Colors.pink[400]),
                                  ),
                                  SizedBox(height: 8),
                                  Text(petData['name'] ?? '小花', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Level ${petData['level'] ?? 1}', style: TextStyle(color: Colors.grey[600])),
                                ],
                              ),
                              // 樹區域
                              Column(
                                children: [
                                  Text('成長之樹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 10),
                                  AnimatedBuilder(
                                    animation: _scaleAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _scaleAnimation.value,
                                        child: Text(
                                          _getTreeStage(completedTasksCount),
                                          style: TextStyle(fontSize: 64),
                                        ),
                                      );
                                    },
                                  ),
                                  Text('今日進度 $completedTasksCount/4', style: TextStyle(color: Colors.grey[600])),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          // 寵物狀態條
                          Column(
                            children: [
                              Row(
                                children: [
                                  Text('經驗值: ${petData['experience'] ?? 0}/100'),
                                  Spacer(),
                                  Text('快樂值: ${petData['happiness'] ?? 50}/100'),
                                ],
                              ),
                              SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: (petData['experience'] ?? 0) / 100.0,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: (petData['happiness'] ?? 50) / 100.0,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[400]!),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 20),

                    // 任務進度條
                    Container(
                      width: double.infinity,
                      height: 15,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[300],
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: completedTasksCount / 4,
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

                    SizedBox(height: 20),

                    // 任務列表
                    Text(
                      '今日任務',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    SizedBox(height: 15),

                    ...tasks.map((task) {
                      bool isCompleted = taskCompletions[task['title']] ?? false;
                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: task['color'][400],
                              child: Icon(task['icon'], color: Colors.white),
                            ),
                            title: Text(
                              task['title'],
                              style: TextStyle(
                                decoration: isCompleted ? TextDecoration.lineThrough : null,
                                color: isCompleted ? Colors.grey : Colors.black87,
                              ),
                            ),
                            subtitle: Text(task['subtitle']),
                            trailing: isCompleted
                                ? Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check, color: Colors.green[700], size: 20),
                            )
                                : ElevatedButton(
                              onPressed: () => _openTaskDetail(task['title']),
                              child: Text('開始'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: task['color'][400],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    // 完成慶祝區域
                    if (completedTasksCount >= 4) ...[
                      SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.yellow.shade100, Colors.orange.shade100],
                          ),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '🎊 今日任務全部完成！ 🎊',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '你的寵物和樹都成長了！\n明天繼續加油！',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
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
      },
    );
  }
}

// 喝水任務
class DrinkingTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const DrinkingTask({Key? key, required this.onCompleted}) : super(key: key);

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
        title: Text('喝水任務 💧'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.blue[50],
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '今日喝水目標',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                Text(
                  '$glasses / $targetGlasses 杯',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 30),
                LinearProgressIndicator(
                  value: glasses / targetGlasses,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.blue,
                ),
                SizedBox(height: 40),
                ElevatedButton(
                  onPressed: glasses < targetGlasses
                      ? () {
                    setState(() {
                      glasses++;
                      if (glasses >= targetGlasses) {
                        Future.delayed(Duration(milliseconds: 500), () {
                          widget.onCompleted();
                          Navigator.of(context).pop();
                        });
                      }
                    });
                  }
                      : null,
                  child: Text('喝一杯水 🥤', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                ),
                SizedBox(height: 20),
                if (glasses >= targetGlasses)
                  Text(
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

  const ExerciseTask({Key? key, required this.onCompleted}) : super(key: key);

  @override
  State<ExerciseTask> createState() => _ExerciseTaskState();
}

class _ExerciseTaskState extends State<ExerciseTask> {
  int seconds = 0;
  final int targetSeconds = 600; // 10分鐘
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
      timer = Timer.periodic(Duration(seconds: 1), (timer) {
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
        title: Text('運動任務 🏃‍♂️'),
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.green[50],
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '運動計時器',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                Text(
                  _formatTime(seconds),
                  style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  '目標：${_formatTime(targetSeconds)}',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 30),
                LinearProgressIndicator(
                  value: seconds / targetSeconds,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.green,
                ),
                SizedBox(height: 40),
                ElevatedButton(
                  onPressed: seconds < targetSeconds ? _toggleTimer : null,
                  child: Text(
                    isRunning ? '暫停 ⏸️' : '開始運動 ▶️',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                ),
                SizedBox(height: 20),
                if (seconds >= targetSeconds)
                  Text(
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

  const MeditationTask({Key? key, required this.onCompleted}) : super(key: key);

  @override
  State<MeditationTask> createState() => _MeditationTaskState();
}

class _MeditationTaskState extends State<MeditationTask> with TickerProviderStateMixin {
  int seconds = 0;
  final int targetSeconds = 300; // 5分鐘
  bool isRunning = false;
  Timer? timer;
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      duration: Duration(seconds: 4),
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
      timer = Timer.periodic(Duration(seconds: 1), (timer) {
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
        title: Text('冥想任務 🧘'),
        backgroundColor: Colors.purple[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.purple[50],
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '冥想計時器',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 40),
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
                            colors: [Colors.purple[200]!, Colors.purple[400]!],
                          ),
                        ),
                        child: Center(
                          child: Text('🧘', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 40),
                Text(
                  _formatTime(seconds),
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  '目標：${_formatTime(targetSeconds)}',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 30),
                LinearProgressIndicator(
                  value: seconds / targetSeconds,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  color: Colors.purple,
                ),
                SizedBox(height: 40),
                ElevatedButton(
                  onPressed: seconds < targetSeconds ? _toggleMeditation : null,
                  child: Text(
                    isRunning ? '停止冥想 ⏸️' : '開始冥想 ▶️',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                ),
                if (isRunning) ...[
                  SizedBox(height: 20),
                  Text(
                    '深呼吸，跟著圓圈的節奏...',
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ],
                SizedBox(height: 20),
                if (seconds >= targetSeconds)
                  Text(
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

// 寫日記任務（移除字數限制）
class DiaryTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const DiaryTask({Key? key, required this.onCompleted}) : super(key: key);

  @override
  State<DiaryTask> createState() => _DiaryTaskState();
}

class _DiaryTaskState extends State<DiaryTask> {
  final TextEditingController _diaryController = TextEditingController();

  @override
  void dispose() {
    _diaryController.dispose();
    super.dispose();
  }

  void _completeDiary() {
    if (_diaryController.text.trim().isNotEmpty) {
      widget.onCompleted();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請至少寫一些內容')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('心情日記 📖'),
        backgroundColor: Colors.orange[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.orange[50],
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天是 ${DateTime.now().month}/${DateTime.now().day}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                '寫下你今天的心情和想法...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _diaryController,
                    maxLines: null,
                    expands: true,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '開始寫下你的心情...\n\n你今天過得怎麼樣？\n有什麼特別的事情發生嗎？\n你現在的感受是什麼？',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    style: TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: _completeDiary,
                  child: Text('完成日記', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// 感恩練習任務
class GratitudeTask extends StatefulWidget {
  final VoidCallback onCompleted;

  const GratitudeTask({Key? key, required this.onCompleted}) : super(key: key);

  @override
  State<GratitudeTask> createState() => _GratitudeTaskState();
}

class _GratitudeTaskState extends State<GratitudeTask> {
  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  final List<String> _prompts = [
    '今天讓你感到感恩的人是誰？',
    '今天發生了什麼讓你覺得幸運的事？',
    '今天有什麼小事讓你感到開心？',
  ];

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _canComplete() {
    return _controllers.every((controller) => controller.text.trim().isNotEmpty);
  }

  void _completeGratitude() {
    if (_canComplete()) {
      widget.onCompleted();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請完成所有感恩練習')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('感恩練習 💕'),
        backgroundColor: Colors.pink[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.pink[50],
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天是 ${DateTime.now().month}/${DateTime.now().day}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                '寫下今天讓你感恩的三件事...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 20),
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${_prompts[index]}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.pink[700],
                            ),
                          ),
                          SizedBox(height: 10),
                          TextField(
                            controller: _controllers[index],
                            maxLines: 3,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: '在這裡寫下你的感恩...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                            ),
                            style: TextStyle(fontSize: 16, height: 1.5),
                            onChanged: (text) {
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: _canComplete() ? _completeGratitude : null,
                  child: Text('完成感恩練習', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canComplete() ? Colors.pink[600] : Colors.grey[400],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

        // 在客戶端排序，避免 Firestore 複合索引問題
        records.sort((a, b) {
          var aData = a.data() as Map<String, dynamic>;
          var bData = b.data() as Map<String, dynamic>;
          var aTime = aData['recordedAt'] as Timestamp?;
          var bTime = bData['recordedAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

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

// 舒緩心理頁面
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

// 戳泡泡紙遊戲
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

// 呼吸冥想遊戲
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
      });
    });
  }

  void _startBreathingCycle() {
    _breathCycle();
  }

  void _breathCycle() async {
    if (!isActive) return;

    setState(() {
      breathText = "吸氣";
      phaseText = "慢慢吸氣，感受空氣進入";
    });
    _breathController.forward(from: 0);
    await Future.delayed(Duration(seconds: 4));

    if (!isActive) return;

    setState(() {
      breathText = "憋氣";
      phaseText = "保持呼吸，讓身體放鬆";
    });
    await Future.delayed(Duration(seconds: 4));

    if (!isActive) return;

    setState(() {
      breathText = "吐氣";
      phaseText = "慢慢吐氣，釋放壓力";
    });
    _breathController.reverse();
    await Future.delayed(Duration(seconds: 4));

    _breathCycle();
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
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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

// 情緒釋放頁面
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

// 療癒語錄頁面
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