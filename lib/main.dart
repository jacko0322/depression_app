import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 確保 Firebase 初始化完成後再檢查認證狀態
  print('Firebase 初始化完成');
  User? currentUser = FirebaseAuth.instance.currentUser;
  print('應用啟動時的用戶狀態: ${currentUser?.email ?? "未登入"}');

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
      // 確保路由正確處理
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(builder: (context) => LoginPage());
          case '/main':
            return MaterialPageRoute(builder: (context) => MainHomePage());
          default:
            return MaterialPageRoute(builder: (context) => AuthWrapper());
        }
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;
  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initializeAuthAsync();
  }

  Future<void> _initializeAuthAsync() async {
    try {
      print('AuthWrapper - 開始異步初始化');
      await Future.delayed(Duration(milliseconds: 100));

      _currentUser = FirebaseAuth.instance.currentUser;
      print('AuthWrapper - 當前用戶: ${_currentUser?.email ?? "未登入"}');

      _setupAuthListener();

      if (mounted && !_isDisposed) {
        setState(() {
          _isInitialized = true;
        });
      }

      print('AuthWrapper - 初始化完成');
    } catch (e) {
      print('AuthWrapper - 初始化錯誤: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  void _setupAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
          (User? user) {
        print('AuthWrapper - 認證狀態變化: ${user?.email ?? "未登入"}');

        if (mounted && !_isDisposed) {
          scheduleMicrotask(() {
            if (mounted && !_isDisposed) {
              setState(() {
                _currentUser = user;
              });
            }
          });
        }
      },
      onError: (error) {
        print('AuthWrapper - 認證監聽錯誤: $error');
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return SplashScreen();
    }

    if (_currentUser != null) {
      print('用戶已登入: ${_currentUser?.email}');
      return QuestionnaireWrapper();
    } else {
      print('用戶未登入，顯示登入頁面');
      return LoginPage();
    }
  }
}


// 2. 修復後的 QuestionnaireWrapper - 添加權限檢查
class QuestionnaireWrapper extends StatefulWidget {
  @override
  _QuestionnaireWrapperState createState() => _QuestionnaireWrapperState();
}

class _QuestionnaireWrapperState extends State<QuestionnaireWrapper> {
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    print('QuestionnaireWrapper - 用戶ID: $userId');

    if (userId == null) {
      print('QuestionnaireWrapper - 用戶ID為空，返回登入頁面');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
          );
        }
      });
      return;
    }

    try {
      // 確保用戶文檔存在
      await _ensureUserDocumentExists(userId);

      // 設置 Firestore 監聽器（包含權限檢查）
      _setupUserDocListener(userId);
    } catch (e) {
      print('QuestionnaireWrapper - 初始化失敗: $e');
      _showErrorAndRedirect(e.toString());
    }
  }

  void _setupUserDocListener(String userId) {
    _userDocSubscription?.cancel();

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (DocumentSnapshot snapshot) {
        if (mounted && !_isDisposed && snapshot.exists) {
          Map<String, dynamic> userData = snapshot.data() as Map<String, dynamic>;
          print('QuestionnaireWrapper - 用戶資料: ${userData.keys.toList()}');

          bool needsQuestionnaire = _shouldShowQuestionnaire(userData);
          print('QuestionnaireWrapper - 是否需要問卷: $needsQuestionnaire');

          if (needsQuestionnaire) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => BDIWelcomeScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => MainHomePage()),
            );
          }
        }
      },
      onError: (error) {
        print('QuestionnaireWrapper - Firestore 監聽錯誤: $error');
        if (error.toString().contains('PERMISSION_DENIED')) {
          print('權限被拒絕，可能用戶已登出');
          _handlePermissionDenied();
        }
      },
    );
  }

  void _handlePermissionDenied() {
    if (mounted && !_isDisposed) {
      // 權限被拒絕通常表示用戶已登出，重定向到登入頁面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    }
  }

  Future<void> _ensureUserDocumentExists(String userId) async {
    try {
      DocumentReference userDocRef = FirebaseFirestore.instance.collection('users').doc(userId);
      DocumentSnapshot userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception('用戶已登出');
        }

        String displayName = currentUser.displayName ??
            currentUser.email?.split('@')[0] ??
            '用戶${userId.substring(0, 6)}';

        await userDocRef.set({
          'email': currentUser.email,
          'displayName': displayName,
          'photoURL': currentUser.photoURL,
          'role': '個人使用者',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'signInMethod': currentUser.providerData.isNotEmpty
              ? currentUser.providerData.first.providerId
              : 'email',
          'isAnonymous': false,
          'questionnaireCompleted': false,
          'lastQuestionnaireDate': null,
          'lastQuestionnaireScore': null,
          'lastQuestionnaireLevel': null,
        });

        print('用戶文檔創建成功');
      }
    } catch (e) {
      print('確保用戶文檔存在時出錯: $e');
      rethrow;
    }
  }

  bool _shouldShowQuestionnaire(Map<String, dynamic> userData) {
    try {
      if (!userData.containsKey('lastQuestionnaireDate') ||
          userData['lastQuestionnaireDate'] == null) {
        return true;
      }

      Timestamp? lastQuestionnaireDate = userData['lastQuestionnaireDate'];
      if (lastQuestionnaireDate == null) {
        return true;
      }

      DateTime lastDate = lastQuestionnaireDate.toDate();
      DateTime now = DateTime.now();
      int daysDifference = now.difference(lastDate).inDays;

      return daysDifference >= 14;
    } catch (e) {
      print('檢查問卷狀態時出錯: $e');
      return true;
    }
  }

  void _showErrorAndRedirect(String error) {
    if (mounted && !_isDisposed) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('載入錯誤'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => LoginPage()),
                );
              },
              child: Text('重新登入'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _userDocSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen();
  }
}

// BDI 問卷歡迎頁面
class BDIWelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue, Colors.lightBlueAccent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.psychology, size: 80, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  'BDI 憂鬱症檢測',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Beck Depression Inventory',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white, size: 32),
                      SizedBox(height: 12),
                      Text(
                        '本檢測包含21個問題，每題有4個選項\n請根據過去兩週的感受誠實回答\n檢測結果僅供參考，如有需要請諮詢專業醫師',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => BDIForm()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 8,
                  ),
                  child: const Text(
                    '開始檢測',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// BDI 問卷表單
class BDIForm extends StatefulWidget {
  @override
  State<BDIForm> createState() => _BDIFormState();
}

class _BDIFormState extends State<BDIForm> with TickerProviderStateMixin {
  List<int> answers = List.filled(21, -1);
  int currentQuestionIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // BDI標準問題及選項
  final List<Map<String, dynamic>> bdiQuestions = [
    {
      'question': '悲傷感',
      'options': ['我不感到悲傷', '我大部分時間感到悲傷', '我一直感到悲傷', '我感到極度悲傷或不快樂，無法忍受'],
    },
    {
      'question': '悲觀',
      'options': ['我對未來不特別沮喪', '我對未來感到沮喪', '我覺得沒有什麼可期待的', '我覺得未來是絕望的，情況不會好轉'],
    },
    {
      'question': '過去的失敗',
      'options': [
        '我不覺得自己是個失敗者',
        '我覺得我比一般人失敗得更多',
        '當我回顧過去，我看到很多失敗',
        '我覺得我是個完全失敗的人',
      ],
    },
    {
      'question': '快樂的喪失',
      'options': [
        '我從事情中得到的滿足感和過去一樣',
        '我不像過去那樣享受事物',
        '我從任何事情中都得不到真正的滿足',
        '我對一切都不滿意或感到厭倦',
      ],
    },
    {
      'question': '罪惡感',
      'options': ['我不特別感到內疚', '我有很多時候感到內疚', '我大部分時間感到內疚', '我一直感到內疚'],
    },
    {
      'question': '懲罰感',
      'options': ['我不覺得我正在被懲罰', '我覺得我可能被懲罰', '我預期會被懲罰', '我覺得我正在被懲罰'],
    },
    {
      'question': '自我厭惡',
      'options': ['我對自己的感覺和過去一樣', '我對自己失去了信心', '我對自己失望', '我討厭自己'],
    },
    {
      'question': '自我指責',
      'options': [
        '我不會比平時更嚴厲地批評或責備自己',
        '我比過去更批評自己',
        '我為自己做錯的每件事責備自己',
        '我為發生的每件壞事責備自己',
      ],
    },
    {
      'question': '自殺念頭或願望',
      'options': ['我沒有任何自殺的念頭', '我有自殺的念頭，但我不會執行', '我想要自殺', '如果有機會，我會自殺'],
    },
    {
      'question': '哭泣',
      'options': ['我哭泣的次數不比過去多', '我比過去哭得更多', '我為每一件小事哭泣', '我想哭，但哭不出來'],
    },
    {
      'question': '激動',
      'options': [
        '我不比平時更煩躁或焦慮',
        '我比平時更容易煩躁或激動',
        '我感到非常煩躁或激動',
        '我太煩躁或激動以至於無法靜下來',
      ],
    },
    {
      'question': '失去興趣',
      'options': [
        '我對其他人或活動的興趣沒有改變',
        '我對人或活動的興趣比以前少',
        '我對大多數事情失去了興趣',
        '我對一切都失去了興趣',
      ],
    },
    {
      'question': '猶豫不決',
      'options': ['我做決定的能力和過去一樣好', '我比過去更難做決定', '我在做決定時遇到很大困難', '我再也無法做任何決定'],
    },
    {
      'question': '無價值感',
      'options': [
        '我不覺得自己沒有價值',
        '我認為自己不如其他人有價值或有用',
        '我覺得自己比其他人更沒有價值',
        '我覺得自己完全沒有價值',
      ],
    },
    {
      'question': '失去活力',
      'options': ['我的活力和過去一樣', '我比過去活力更少', '我沒有足夠的活力做很多事', '我沒有活力做任何事'],
    },
    {
      'question': '睡眠模式改變',
      'options': [
        '我的睡眠模式沒有改變',
        '我比平時睡得更多或更少',
        '我比平時早醒2小時且難以重新入睡',
        '我比平時早醒幾個小時且無法重新入睡',
      ],
    },
    {
      'question': '易怒',
      'options': ['我不比平時更易怒', '我比平時更易怒', '我比平時易怒得多', '我一直都很易怒'],
    },
    {
      'question': '食慾改變',
      'options': ['我的食慾沒有改變', '我的食慾比以前稍差', '我的食慾比以前差很多', '我完全沒有食慾'],
    },
    {
      'question': '專注困難',
      'options': [
        '我能像過去一樣集中注意力',
        '我不能像過去那樣集中注意力',
        '我很難長時間專注於任何事情',
        '我發現我無法專注於任何事情',
      ],
    },
    {
      'question': '疲倦或疲勞',
      'options': [
        '我不比平時更疲倦或疲勞',
        '我比平時更容易疲倦或疲勞',
        '我太疲倦或疲勞以至於無法做很多過去做的事',
        '我太疲倦或疲勞以至於無法做大部分過去做的事',
      ],
    },
    {
      'question': '對性的興趣喪失',
      'options': ['我對性的興趣沒有明顯改變', '我對性的興趣比以前少', '我對性的興趣明顯減少', '我完全失去了對性的興趣'],
    },
  ];

  int calculateBDIScore() {
    return answers
        .where((answer) => answer != -1)
        .fold(0, (sum, answer) => sum + answer);
  }

  String getResultInterpretation(int score) {
    if (score <= 13) {
      return '無或極輕微憂鬱';
    } else if (score <= 19) {
      return '輕度憂鬱';
    } else if (score <= 28) {
      return '中度憂鬱';
    } else {
      return '重度憂鬱';
    }
  }

  Color getResultColor(int score) {
    if (score <= 13) {
      return Colors.green;
    } else if (score <= 19) {
      return Colors.orange;
    } else if (score <= 28) {
      return Colors.deepOrange;
    } else {
      return Colors.red;
    }
  }

  String getResultDescription(int score) {
    if (score <= 13) {
      return '您的憂鬱程度在正常範圍內，情緒狀態良好。';
    } else if (score <= 19) {
      return '您可能存在輕度憂鬱傾向，建議關注自己的情緒狀態。';
    } else if (score <= 28) {
      return '您可能存在中度憂鬱傾向，建議尋求專業心理諮詢。';
    } else {
      return '您可能存在重度憂鬱傾向，強烈建議儘快尋求專業醫療協助。';
    }
  }

  Future<void> _saveQuestionnaireResult(int score) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      // 獲取當前時間
      DateTime now = DateTime.now();

      // 準備詳細的答案記錄
      List<Map<String, dynamic>> detailedAnswers = [];
      for (int i = 0; i < bdiQuestions.length; i++) {
        detailedAnswers.add({
          'questionIndex': i,
          'question': bdiQuestions[i]['question'],
          'selectedOption': answers[i],
          'optionText': answers[i] >= 0 ? bdiQuestions[i]['options'][answers[i]] : '',
          'score': answers[i],
        });
      }

      // 儲存詳細問卷結果
      DocumentReference questionnaireRef = await FirebaseFirestore.instance
          .collection('questionnaire_results')
          .add({
        'userId': userId,
        'score': score,
        'level': getResultInterpretation(score),
        'description': getResultDescription(score),
        'completedAt': FieldValue.serverTimestamp(),
        'completedDate': now.toIso8601String().split('T')[0], // 日期字串
        'answers': answers, // 原始答案陣列
        'detailedAnswers': detailedAnswers, // 詳細答案記錄
        'questionnaireType': 'BDI',
        'questionnaireVersion': '1.0',
      });

      print('問卷結果儲存成功，ID: ${questionnaireRef.id}');

      // 更新用戶的最後問卷資料
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
        'lastQuestionnaireDate': FieldValue.serverTimestamp(),
        'lastQuestionnaireScore': score,
        'lastQuestionnaireLevel': getResultInterpretation(score),
        'lastQuestionnaireId': questionnaireRef.id,
        'questionnaireCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('用戶資料更新成功');
    } catch (e) {
      print('儲存問卷結果失敗: $e');
      // 顯示錯誤訊息給用戶
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('儲存失敗：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showResult() {
    int score = calculateBDIScore();
    String result = getResultInterpretation(score);
    Color resultColor = getResultColor(score);
    String description = getResultDescription(score);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.assessment, color: resultColor, size: 32),
            const SizedBox(width: 12),
            const Text('檢測結果'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: resultColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: resultColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '總分: $score 分',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: resultColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: resultColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 重要提醒：本檢測結果僅供參考，不能替代專業醫療診斷。如有需要，請諮詢專業醫師或心理健康專家。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              // 顯示載入狀態
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => Center(
                  child: CircularProgressIndicator(),
                ),
              );

              try {
                await _saveQuestionnaireResult(score);
                // 關閉載入對話框
                Navigator.of(context).pop();
                // 關閉結果對話框
                Navigator.of(context).pop();
                // 強制導航到主頁面
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => MainHomePage()),
                      (route) => false,
                );
              } catch (e) {
                // 關閉載入對話框
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('儲存失敗，請重試'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('進入應用'),
          ),
        ],
      ),
    );
  }

  void _nextQuestion() {
    if (answers[currentQuestionIndex] == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請選擇一個選項後再繼續'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _animationController.reset();
    if (currentQuestionIndex < 20) {
      setState(() {
        currentQuestionIndex++;
      });
      _animationController.forward();
    } else {
      _showResult();
    }
  }

  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      _animationController.reset();
      setState(() {
        currentQuestionIndex--;
      });
      _animationController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    double progress = (currentQuestionIndex + 1) / 21;

    return Scaffold(
      appBar: AppBar(
        title: Text('問題 ${currentQuestionIndex + 1} / 21'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // 禁用返回按鈕
      ),
      body: Column(
        children: [
          // 進度條
          Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // 問題內容
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 問題標題
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Text(
                        bdiQuestions[currentQuestionIndex]['question'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 選項
                    ...List.generate(4, (index) {
                      bool isSelected = answers[currentQuestionIndex] == index;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : Colors.grey.withOpacity(0.3),
                            width: isSelected ? 2 : 1,
                          ),
                          color: isSelected
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.white,
                        ),
                        child: RadioListTile<int>(
                          title: Text(
                            bdiQuestions[currentQuestionIndex]['options'][index],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected ? Colors.blue : Colors.black87,
                            ),
                          ),
                          value: index,
                          groupValue: answers[currentQuestionIndex],
                          onChanged: (value) {
                            setState(() {
                              answers[currentQuestionIndex] = value!;
                            });
                          },
                          activeColor: Colors.blue,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          // 按鈕區域
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 上一題按鈕
                if (currentQuestionIndex > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousQuestion,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('上一題'),
                    ),
                  ),

                if (currentQuestionIndex > 0) const SizedBox(width: 16),

                // 下一題/提交按鈕
                Expanded(
                  child: ElevatedButton(
                    onPressed: _nextQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      currentQuestionIndex < 20 ? '下一題' : '提交結果',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

// 修復類型轉換錯誤的 LoginPage
class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkAuthState();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  Future<void> _checkAuthState() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      print('檢測到用戶已登入: ${user.email}，但仍在登入頁面');
    } else {
      print('用戶未登入，正確顯示登入頁面');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 40),
                    _buildHeader(),
                    SizedBox(height: 40),
                    _buildEmailField(),
                    SizedBox(height: 16),
                    _buildPasswordField(),
                    SizedBox(height: 24),
                    _buildEmailAuthButton(),
                    SizedBox(height: 20),
                    _buildDivider(),
                    SizedBox(height: 20),
                    _buildGoogleSignInButton(),
                    SizedBox(height: 24),
                    _buildToggleButton(),
                    SizedBox(height: 16),
                    _buildForgotPasswordButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.blue[300]!, Colors.blue[600]!],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.psychology,
            size: 50,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 24),
        Text(
          _isLogin ? '歡迎回來' : '建立帳戶',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        SizedBox(height: 8),
        Text(
          _isLogin ? '登入您的帳戶繼續使用' : '註冊新帳戶開始您的心靈之旅',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: '電子郵件',
        hintText: '請輸入您的電子郵件',
        prefixIcon: Icon(Icons.email_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '請輸入電子郵件';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          return '請輸入有效的電子郵件格式';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: '密碼',
        hintText: _isLogin ? '請輸入您的密碼' : '請設定密碼（至少6位）',
        prefixIcon: Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '請輸入密碼';
        }
        if (value.length < 6) {
          return '密碼至少需要6位字符';
        }
        return null;
      },
    );
  }

  Widget _buildEmailAuthButton() {
    return Container(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleEmailAuth,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('處理中...', style: TextStyle(fontSize: 16)),
          ],
        )
            : Text(
          _isLogin ? '登入' : '註冊',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300])),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '或',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey[300])),
      ],
    );
  }

  Widget _buildGoogleSignInButton() {
    return Container(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: Container(
          width: 20,
          height: 20,
          child: Icon(Icons.login, color: Colors.red[600], size: 20),
        ),
        label: Text(
          '使用 Google 登入',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey[700],
          side: BorderSide(color: Colors.grey[300]!, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? '還沒有帳戶？' : '已有帳戶？',
          style: TextStyle(color: Colors.grey[600]),
        ),
        TextButton(
          onPressed: _isLoading ? null : () {
            setState(() {
              _isLogin = !_isLogin;
              _formKey.currentState?.reset();
            });
          },
          child: Text(
            _isLogin ? '立即註冊' : '立即登入',
            style: TextStyle(
              color: Colors.blue[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordButton() {
    if (!_isLogin) return SizedBox.shrink();

    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : _showForgotPasswordDialog,
        child: Text(
          '忘記密碼？',
          style: TextStyle(
            color: Colors.blue[600],
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  // 修復後的 Email/Password 登入邏輯
  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential;

      if (_isLogin) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        print('Email 登入成功: ${userCredential.user?.email}');
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        print('Email 註冊成功: ${userCredential.user?.email}');
      }

      // 修復後的後處理 - 增加錯誤捕獲
      await _handlePostLoginSafely(userCredential);

    } catch (e) {
      print('Email 登入/註冊失敗: $e');
      // 檢查是否實際上已經登入成功
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('雖然出現錯誤，但用戶實際已登入: ${currentUser.email}');
        // 直接導航，不顯示錯誤
        _navigateToApp();
      } else {
        _showErrorMessage(_getErrorMessage(e.toString()));
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  // 修復後的 Google 登入邏輯
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 確保清除之前的狀態
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print('Google 登入被取消');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      print('Google 登入成功: ${userCredential.user?.email}');

      // 修復後的後處理 - 增加錯誤捕獲
      await _handlePostLoginSafely(userCredential);

    } catch (e) {
      print('Google 登入失敗: $e');
      // 檢查是否實際上已經登入成功
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('雖然出現錯誤，但用戶實際已登入: ${currentUser.email}');
        // 直接導航，不顯示錯誤
        _navigateToApp();
      } else {
        _showErrorMessage('Google登入失敗：${_getErrorMessage(e.toString())}');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  // 安全的登入後處理 - 包裝錯誤處理
  Future<void> _handlePostLoginSafely(UserCredential userCredential) async {
    try {
      print('登入成功，開始後處理流程');

      // 安全地創建或更新用戶文檔
      await _createOrUpdateUserDocumentSafely(userCredential.user!);

      print('用戶文檔處理完成');

      // 顯示成功訊息
      _showSuccessMessage(_isLogin ? '登入成功！' : '註冊成功！');

      // 導航到應用
      _navigateToApp();

    } catch (e) {
      print('登入後處理失敗: $e');
      // 即使後處理失敗，如果用戶已登入，還是導航到應用
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('後處理失敗但用戶已登入，直接進入應用');
        _navigateToApp();
      } else {
        _showErrorMessage('登入後處理失敗：$e');
      }
    }
  }

  // 安全的用戶文檔創建/更新
  Future<void> _createOrUpdateUserDocumentSafely(User user) async {
    try {
      DocumentReference userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      DocumentSnapshot userDoc = await userDocRef.get();

      // 安全地獲取顯示名稱，避免類型轉換錯誤
      String displayName;
      try {
        displayName = user.displayName ??
            user.email?.split('@')[0] ??
            '用戶${user.uid.substring(0, 6)}';
      } catch (e) {
        print('獲取顯示名稱時出錯: $e');
        displayName = user.email?.split('@')[0] ?? '用戶${user.uid.substring(0, 6)}';
      }

      Map<String, dynamic> userData = {
        'email': user.email,
        'displayName': displayName,
        'photoURL': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
        'signInMethod': user.providerData.isNotEmpty
            ? user.providerData.first.providerId
            : 'email',
        'isAnonymous': false,
      };

      if (!userDoc.exists) {
        // 新用戶，創建完整文檔
        userData.addAll({
          'role': '個人使用者',
          'createdAt': FieldValue.serverTimestamp(),
          'questionnaireCompleted': false,
          'lastQuestionnaireDate': null,
          'lastQuestionnaireScore': null,
          'lastQuestionnaireLevel': null,
        });

        await userDocRef.set(userData);
        print('新用戶文檔創建成功');
      } else {
        // 現有用戶，只更新必要字段
        await userDocRef.update(userData);
        print('現有用戶文檔更新成功');
      }

      // 安全地更新 Firebase Auth 的 displayName
      try {
        if (user.displayName != displayName) {
          await user.updateDisplayName(displayName);
          print('用戶顯示名稱更新成功');
        }
      } catch (e) {
        print('更新用戶顯示名稱時出錯（可忽略）: $e');
        // 這個錯誤可以忽略，不影響登入功能
      }

    } catch (e) {
      print('創建/更新用戶文檔時出錯: $e');
      // 不要重新拋出錯誤，因為這不應該阻止登入
    }
  }

  // 導航到應用
  void _navigateToApp() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => AuthWrapper()),
            (route) => false,
      );
    }
  }

  // 忘記密碼功能
  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.blue[600]),
            SizedBox(width: 8),
            Text('重設密碼'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('請輸入您的電子郵件地址，我們會發送重設密碼的連結給您。'),
            SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              decoration: InputDecoration(
                labelText: '電子郵件',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              resetEmailController.dispose();
              Navigator.pop(context);
            },
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              String email = resetEmailController.text.trim();
              if (email.isEmpty) {
                _showErrorMessage('請輸入電子郵件地址');
                return;
              }

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                resetEmailController.dispose();
                Navigator.pop(context);
                _showSuccessMessage('重設密碼郵件已發送！請檢查您的信箱。');
              } catch (e) {
                _showErrorMessage('發送重設郵件失敗：${_getErrorMessage(e.toString())}');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: Text('發送'),
          ),
        ],
      ),
    );
  }

  // 訊息顯示方法
  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // 錯誤訊息轉換
  String _getErrorMessage(String error) {
    if (error.contains('user-not-found')) return '找不到此用戶，請檢查電子郵件是否正確';
    if (error.contains('wrong-password')) return '密碼錯誤，請重新輸入';
    if (error.contains('email-already-in-use')) return '此電子郵件已被註冊，請使用其他郵件或直接登入';
    if (error.contains('weak-password')) return '密碼強度不足，請使用至少6位字符';
    if (error.contains('invalid-email')) return '電子郵件格式錯誤，請檢查格式';
    if (error.contains('network-request-failed')) return '網絡連接失敗，請檢查網路連接';
    if (error.contains('too-many-requests')) return '請求過於頻繁，請稍後再試';
    if (error.contains('invalid-credential')) return '登入憑證無效，請重新登入';
    if (error.contains('account-exists-with-different-credential')) {
      return '此郵件已使用其他方式註冊，請嘗試其他登入方式';
    }
    if (error.contains('PigeonUserDetails') || error.contains('type cast')) {
      return '登入處理中出現技術問題，但您已成功登入';
    }
    return '發生未知錯誤，請稍後再試';
  }
}
// 主頁面 - 優化版本，解決 lag 和登出問題
class MainHomePage extends StatefulWidget {
  @override
  _MainHomePageState createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isSigningOut = false;
  bool _isDisposed = false;

  final List<Widget> _pages = [
    IntegratedGrowthPage(),
    MoodRecordPage(),
    CommunityPage(),
    RelaxationPage(),
    EducationPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkUserState();
  }

  // 檢查用戶狀態
  void _checkUserState() {
    User? user = FirebaseAuth.instance.currentUser;
    print('MainHomePage 初始化 - 當前用戶: ${user?.email ?? "未登入"}');

    if (user == null) {
      // 如果沒有用戶，立即導航到登入頁面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => AuthWrapper()),
                (route) => false,
          );
        }
      });
    }
  }

  // 優化的登出功能 - 避免阻塞主線程
  Future<void> _handleSignOut() async {
    if (_isSigningOut) return; // 防止重複點擊

    try {
      // 顯示確認對話框
      bool? confirmSignOut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.logout, color: Colors.red[600]),
              SizedBox(width: 8),
              Text('確認登出'),
            ],
          ),
          content: Text('您確定要登出嗎？\n登出後需要重新登入才能使用應用。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              child: Text('登出'),
            ),
          ],
        ),
      );

      if (confirmSignOut != true) return;

      setState(() {
        _isSigningOut = true;
      });

      print('開始優化登出流程');

      // 顯示載入狀態對話框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '正在登出...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 異步執行登出操作，避免阻塞 UI
      await _performSignOutAsync();

    } catch (e) {
      print('登出失敗: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _isSigningOut = false;
        });

        // 關閉載入對話框
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        _showErrorMessage('登出失敗：${_getErrorMessage(e.toString())}');
      }
    }
  }

  Future<void> _performSignOutAsync() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        print('開始登出用戶: ${user.email}');

        // 使用 Future.wait 並行執行登出操作，避免阻塞
        await Future.wait([
          // 1. 清除 Google Sign-In 狀態
          Future(() async {
            try {
              if (await _googleSignIn.isSignedIn()) {
                await _googleSignIn.disconnect();
                await _googleSignIn.signOut();
                print('Google 登出成功');
              }
            } catch (e) {
              print('Google 登出錯誤: $e');
              // 不要因為 Google 登出失敗就停止整個流程
            }
          }),
          // 2. 清除 Firebase Auth 狀態
          FirebaseAuth.instance.signOut(),
        ]);

        print('所有登出操作完成');

        // 等待狀態完全清除
        await Future.delayed(Duration(milliseconds: 500));

        // 驗證登出狀態
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          print('警告：用戶狀態未完全清除，重試登出');
          await FirebaseAuth.instance.signOut();
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      // 關閉載入對話框
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // 導航到 AuthWrapper 並清除所有路由棧
      if (mounted && !_isDisposed) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => AuthWrapper()),
              (route) => false,
        );
      }

      print('登出流程完成');

      // 延遲顯示成功訊息
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('登出成功'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });

    } catch (e) {
      print('執行登出時出錯: $e');
      rethrow;
    }
  }

  // 顯示問卷歷史
  void _showQuestionnaireHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QuestionnaireHistoryPage()),
    );
  }

  // 顯示用戶資料
  void _showUserProfile() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blue[100],
              backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
              child: user.photoURL == null ? Icon(Icons.person, color: Colors.blue[600]) : null,
            ),
            SizedBox(width: 12),
            Text('個人資料'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileItem('姓名', user.displayName ?? '未設定'),
            SizedBox(height: 8),
            _buildProfileItem('電子郵件', user.email ?? '未知'),
            SizedBox(height: 8),
            _buildProfileItem('登入方式', _getSignInMethod(user)),
            SizedBox(height: 8),
            _buildProfileItem('註冊時間', _formatDate(user.metadata.creationTime)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 2),
        Text(
          value ?? '未知',
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  String _getSignInMethod(User user) {
    if (user.providerData.isEmpty) return '未知';

    String providerId = user.providerData.first.providerId;
    switch (providerId) {
      case 'google.com':
        return 'Google';
      case 'password':
        return '電子郵件';
      default:
        return providerId;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  // 重新填寫問卷
  void _retakeQuestionnaire() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.quiz, color: Colors.blue[600]),
            SizedBox(width: 8),
            Text('重新填寫問卷'),
          ],
        ),
        content: Text('您確定要重新填寫 BDI 憂鬱症檢測問卷嗎？\n\n新的結果會覆蓋之前的記錄。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BDIWelcomeScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: Text('確定'),
          ),
        ],
      ),
    );
  }

  // 顯示錯誤訊息
  void _showErrorMessage(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: Duration(seconds: 4),
          action: SnackBarAction(
            label: '重試',
            textColor: Colors.white,
            onPressed: () => _handleSignOut(),
          ),
        ),
      );
    }
  }

  // 錯誤訊息轉換
  String _getErrorMessage(String error) {
    if (error.contains('network')) {
      return '網路連接問題，請檢查網路後重試';
    } else if (error.contains('permission')) {
      return '權限錯誤，請重新啟動應用';
    } else if (error.contains('timeout')) {
      return '操作超時，請重試';
    }
    return '發生未知錯誤，請稍後再試';
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('心靈陪伴'),
        backgroundColor: Colors.blue[400],
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          // 問卷歷史按鈕
          IconButton(
            onPressed: _isSigningOut ? null : _showQuestionnaireHistory,
            icon: Icon(Icons.history),
            tooltip: '問卷歷史',
          ),

          // 用戶頭像（如果有的話）
          if (currentUser?.photoURL != null && !_isSigningOut)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _showUserProfile,
                child: CircleAvatar(
                  backgroundImage: NetworkImage(currentUser!.photoURL!),
                  radius: 16,
                ),
              ),
            ),

          // 登出狀態指示器或選單按鈕
          if (_isSigningOut)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              tooltip: '更多選項',
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    _showUserProfile();
                    break;
                  case 'questionnaire':
                    _retakeQuestionnaire();
                    break;
                  case 'logout':
                    _handleSignOut();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 20, color: Colors.blue[600]),
                      SizedBox(width: 8),
                      Text('個人資料'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'questionnaire',
                  child: Row(
                    children: [
                      Icon(Icons.quiz, size: 20, color: Colors.green[600]),
                      SizedBox(width: 8),
                      Text('重新填寫問卷'),
                    ],
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red[600]),
                      SizedBox(width: 8),
                      Text('登出', style: TextStyle(color: Colors.red[600])),
                    ],
                  ),
                ),
              ],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _isSigningOut ? null : (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blue[600],
          unselectedItemColor: Colors.grey[600],
          selectedFontSize: 12,
          unselectedFontSize: 10,
          elevation: 0,
          backgroundColor: Colors.white,
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.eco),
              activeIcon: Icon(Icons.eco, size: 28),
              label: '成長花園',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.mood),
              activeIcon: Icon(Icons.mood, size: 28),
              label: '心情記錄',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.forum),
              activeIcon: Icon(Icons.forum, size: 28),
              label: '社群支持',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.spa),
              activeIcon: Icon(Icons.spa, size: 28),
              label: '舒緩心理',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.school),
              activeIcon: Icon(Icons.school, size: 28),
              label: '資源教育',
            ),
          ],
        ),
      ),
    );
  }
}

// 問卷歷史頁面 - 增強顯示內容
class QuestionnaireHistoryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('問卷歷史'),
          backgroundColor: Colors.blue[400],
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login, size: 64, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text('請先登入', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('問卷歷史'),
        backgroundColor: Colors.blue[400],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('questionnaire_results')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                  SizedBox(height: 16),
                  Text('載入錯誤', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 8),
                  Text('${snapshot.error}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            );
          }

          var results = snapshot.data?.docs ?? [];

          // 在客戶端排序
          results.sort((a, b) {
            var aData = a.data() as Map<String, dynamic>;
            var bData = b.data() as Map<String, dynamic>;
            var aTime = aData['completedAt'] as Timestamp?;
            var bTime = bData['completedAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.quiz_outlined, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    '還沒有問卷記錄',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: results.length,
            itemBuilder: (context, index) {
              var result = results[index].data() as Map<String, dynamic>;
              int score = result['score'] ?? 0;
              String level = result['level'] ?? '未知';
              String description = result['description'] ?? '';
              Timestamp? completedAt = result['completedAt'];

              Color resultColor = _getResultColor(score);

              return Card(
                margin: EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: resultColor.withOpacity(0.1),
                    child: Icon(
                      Icons.assessment,
                      color: resultColor,
                    ),
                  ),
                  title: Text(
                    '總分: $score 分',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: resultColor,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        level,
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        completedAt != null ? _formatDate(completedAt.toDate()) : '未知時間',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '詳細說明：',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            description,
                            style: TextStyle(fontSize: 14, height: 1.4),
                          ),
                          SizedBox(height: 12),
                          if (result['detailedAnswers'] != null) ...[
                            Text(
                              '答案詳情：',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            ...((result['detailedAnswers'] as List).take(3).map((answer) {
                              return Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${answer['question']}: ${answer['optionText']}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              );
                            }).toList()),
                            if ((result['detailedAnswers'] as List).length > 3)
                              Text(
                                '... 等共21個問題',
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getResultColor(int score) {
    if (score <= 13) return Colors.green;
    if (score <= 19) return Colors.orange;
    if (score <= 28) return Colors.deepOrange;
    return Colors.red;
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// 社群頁面 - 新增功能1
class CommunityPage extends StatefulWidget {
  @override
  _CommunityPageState createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.forum, color: Colors.blue[600], size: 28),
                    SizedBox(width: 8),
                    Text(
                      '社群支持',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '分享你的感受，獲得同伴的支持與鼓勵 💙',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: '心情廣場'),
              Tab(text: '我的分享'),
            ],
            labelColor: Colors.blue[600],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.blue[600],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SafeCommunityFeedPage(),
                SafeMyPostsPage(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CreatePostPage()),
          );
        },
        child: Icon(Icons.add),
        backgroundColor: Colors.blue[600],
      ),
    );
  }
}

// 4. 安全的社群動態頁面 - 包含權限檢查
class SafeCommunityFeedPage extends StatefulWidget {
  @override
  _SafeCommunityFeedPageState createState() => _SafeCommunityFeedPageState();
}

class _SafeCommunityFeedPageState extends State<SafeCommunityFeedPage> {
  StreamSubscription<QuerySnapshot>? _postsSubscription;
  List<QueryDocumentSnapshot> _posts = [];
  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _setupPostsListener();
  }

  void _setupPostsListener() {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _error = '用戶未登入';
        _isLoading = false;
      });
      return;
    }

    _postsSubscription = FirebaseFirestore.instance
        .collection('community_posts')
        .limit(50)
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
        if (mounted && !_isDisposed) {
          setState(() {
            _posts = snapshot.docs;
            _isLoading = false;
            _error = null;
          });

          // 在客戶端排序
          _posts.sort((a, b) {
            var aData = a.data() as Map<String, dynamic>;
            var bData = b.data() as Map<String, dynamic>;
            var aTime = aData['createdAt'] as Timestamp?;
            var bTime = bData['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
        }
      },
      onError: (error) {
        print('CommunityFeedPage - Firestore 錯誤: $error');
        if (mounted && !_isDisposed) {
          setState(() {
            _error = error.toString();
            _isLoading = false;
          });

          if (error.toString().contains('PERMISSION_DENIED')) {
            // 權限被拒絕，可能需要重新登入
            _handlePermissionError();
          }
        }
      },
    );
  }

  void _handlePermissionError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('權限錯誤'),
        content: Text('無法載入社群內容，請重新登入。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
            child: Text('重新登入'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _postsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            SizedBox(height: 16),
            Text('載入錯誤'),
            SizedBox(height: 8),
            Text(
              '請檢查網路連接或重新登入',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _setupPostsListener();
              },
              child: Text('重試'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              '還沒有人分享心情',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              '成為第一個分享的人吧！',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        var post = _posts[index].data() as Map<String, dynamic>;
        return CommunityPostCard(
          postId: _posts[index].id,
          postData: post,
        );
      },
    );
  }
}

// 5. 安全的個人貼文頁面
class SafeMyPostsPage extends StatefulWidget {
  @override
  _SafeMyPostsPageState createState() => _SafeMyPostsPageState();
}

class _SafeMyPostsPageState extends State<SafeMyPostsPage> {
  StreamSubscription<QuerySnapshot>? _postsSubscription;
  List<QueryDocumentSnapshot> _posts = [];
  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _setupMyPostsListener();
  }

  void _setupMyPostsListener() {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _error = '用戶未登入';
        _isLoading = false;
      });
      return;
    }

    _postsSubscription = FirebaseFirestore.instance
        .collection('community_posts')
        .where('authorId', isEqualTo: userId)
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
        if (mounted && !_isDisposed) {
          setState(() {
            _posts = snapshot.docs;
            _isLoading = false;
            _error = null;
          });

          // 在客戶端排序
          _posts.sort((a, b) {
            var aData = a.data() as Map<String, dynamic>;
            var bData = b.data() as Map<String, dynamic>;
            var aTime = aData['createdAt'] as Timestamp?;
            var bTime = bData['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
        }
      },
      onError: (error) {
        print('MyPostsPage - Firestore 錯誤: $error');
        if (mounted && !_isDisposed) {
          setState(() {
            _error = error.toString();
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _postsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            SizedBox(height: 16),
            Text('載入錯誤'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _setupMyPostsListener();
              },
              child: Text('重試'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_outlined, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              '你還沒有分享過心情',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              '點擊右下角的按鈕開始分享',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        var post = _posts[index].data() as Map<String, dynamic>;
        return CommunityPostCard(
          postId: _posts[index].id,
          postData: post,
          isMyPost: true,
        );
      },
    );
  }
}

// 社群貼文卡片
class CommunityPostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final bool isMyPost;

  const CommunityPostCard({
    Key? key,
    required this.postId,
    required this.postData,
    this.isMyPost = false,
  }) : super(key: key);

  @override
  _CommunityPostCardState createState() => _CommunityPostCardState();
}

class _CommunityPostCardState extends State<CommunityPostCard> {
  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeLikeStatus();
    _initializeCommentCount();
  }

  Future<void> _initializeCommentCount() async {
    try {
      QuerySnapshot commentQuery = await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(widget.postId)
          .collection('comments')
          .get();

      setState(() {
        _commentCount = commentQuery.docs.length;
      });
    } catch (e) {
      print('初始化評論計數錯誤: $e');
    }
  }

  Future<void> _initializeLikeStatus() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      // 檢查是否已點讚
      QuerySnapshot likeQuery = await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(widget.postId)
          .collection('likes')
          .where('userId', isEqualTo: userId)
          .get();

      // 獲取點讚總數
      QuerySnapshot allLikesQuery = await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(widget.postId)
          .collection('likes')
          .get();

      setState(() {
        _isLiked = likeQuery.docs.isNotEmpty;
        _likeCount = allLikesQuery.docs.length;
      });
    } catch (e) {
      print('初始化點讚狀態錯誤: $e');
    }
  }

  Future<void> _toggleLike() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請先登入才能點讚')),
      );
      return;
    }

    try {
      if (_isLiked) {
        // 取消點讚 - 查找並刪除對應的點讚記錄
        QuerySnapshot likeQuery = await FirebaseFirestore.instance
            .collection('community_posts')
            .doc(widget.postId)
            .collection('likes')
            .where('userId', isEqualTo: userId)
            .get();

        for (QueryDocumentSnapshot doc in likeQuery.docs) {
          await doc.reference.delete();
        }

        print('取消點讚成功');

        setState(() {
          _isLiked = false;
          _likeCount--;
        });
      } else {
        // 新增點讚
        DocumentReference likeRef = await FirebaseFirestore.instance
            .collection('community_posts')
            .doc(widget.postId)
            .collection('likes')
            .add({
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('點讚成功，ID: ${likeRef.id}');

        setState(() {
          _isLiked = true;
          _likeCount++;
        });
      }
    } catch (e) {
      print('點讚操作錯誤: $e');
      String errorMessage = '點讚失敗';
      if (e.toString().contains('permission-denied')) {
        errorMessage = '權限不足，請檢查 Firebase 設定';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorMessage，請稍後再試')),
      );
    }
  }

  void _openComments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostCommentsPage(postId: widget.postId),
      ),
    ).then((_) {
      // 當評論頁面關閉後，重新載入評論計數
      _initializeCommentCount();
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '剛剛';

    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();
    Duration difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  String _getMoodEmoji(String mood) {
    switch (mood) {
      case 'happy': return '😊';
      case 'sad': return '😢';
      case 'anxious': return '😰';
      case 'calm': return '😌';
      case 'excited': return '🤩';
      case 'tired': return '😴';
      case 'grateful': return '🙏';
      case 'confused': return '🤔';
      default: return '💭';
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAnonymous = widget.postData['isAnonymous'] ?? false;
    String authorName = isAnonymous ? '匿名用戶' : (widget.postData['authorName'] ?? '用戶');

    // 如果顯示名稱為 '未知用戶'，嘗試從 email 中提取用戶名
    if (authorName == '未知用戶' && widget.postData['authorEmail'] != null) {
      authorName = widget.postData['authorEmail'].split('@')[0];
    }

    String mood = widget.postData['mood'] ?? 'normal';

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用戶信息行
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.blue[100],
                  child: isAnonymous
                      ? Icon(Icons.person, color: Colors.blue[600])
                      : (widget.postData['authorPhotoURL'] != null
                      ? null
                      : Icon(Icons.person, color: Colors.blue[600])),
                  backgroundImage: (!isAnonymous && widget.postData['authorPhotoURL'] != null)
                      ? NetworkImage(widget.postData['authorPhotoURL'])
                      : null,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            authorName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            _getMoodEmoji(mood),
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      Text(
                        _formatTimestamp(widget.postData['createdAt']),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isMyPost)
                  PopupMenuButton(
                    icon: Icon(Icons.more_horiz),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteConfirmation();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('刪除'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 12),

            // 貼文內容
            Text(
              widget.postData['content'] ?? '',
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
              ),
            ),

            SizedBox(height: 16),

            // 互動按鈕
            Row(
              children: [
                GestureDetector(
                  onTap: _toggleLike,
                  child: Row(
                    children: [
                      Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.grey[600],
                        size: 20,
                      ),
                      SizedBox(width: 4),
                      Text(
                        _likeCount.toString(),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 24),
                GestureDetector(
                  onTap: _openComments,
                  child: Row(
                    children: [
                      Icon(Icons.comment_outlined, color: Colors.grey[600], size: 20),
                      SizedBox(width: 4),
                      Text(
                        _commentCount.toString(),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                if (!widget.isMyPost)
                  GestureDetector(
                    onTap: _showReportDialog,
                    child: Icon(Icons.report_outlined, color: Colors.grey[600], size: 20),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('刪除貼文'),
        content: Text('確定要刪除這則貼文嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    try {
      await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(widget.postId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('貼文已刪除')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗：$e')),
      );
    }
  }

  void _showReportDialog() {
    final List<String> reportReasons = [
      '不當內容',
      '騷擾或霸凌',
      '垃圾訊息',
      '虛假資訊',
      '其他'
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('檢舉貼文'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('請選擇檢舉原因：'),
            SizedBox(height: 12),
            ...reportReasons.map((reason) =>
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason, style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _reportPost(reason);
                  },
                ),
            ).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _reportPost(String reason) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請先登入才能檢舉')),
      );
      return;
    }

    try {
      DocumentReference reportRef = await FirebaseFirestore.instance.collection('reports').add({
        'postId': widget.postId,
        'reportedBy': userId,
        'reportedAt': FieldValue.serverTimestamp(),
        'type': 'post',
        'reason': reason,
      });

      print('檢舉成功，ID: ${reportRef.id}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('檢舉已提交，謝謝您的反饋')),
      );
    } catch (e) {
      print('檢舉失敗: $e');
      String errorMessage = '檢舉失敗';
      if (e.toString().contains('permission-denied')) {
        errorMessage = '權限不足，請檢查 Firebase 設定';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorMessage，請稍後再試')),
      );
    }
  }
}

// 發布貼文頁面
class CreatePostPage extends StatefulWidget {
  @override
  _CreatePostPageState createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _contentController = TextEditingController();
  bool _isAnonymous = false;
  String _selectedMood = 'normal';
  bool _isLoading = false;

  final List<Map<String, dynamic>> _moods = [
    {'key': 'happy', 'emoji': '😊', 'label': '開心'},
    {'key': 'sad', 'emoji': '😢', 'label': '難過'},
    {'key': 'anxious', 'emoji': '😰', 'label': '焦慮'},
    {'key': 'calm', 'emoji': '😌', 'label': '平靜'},
    {'key': 'excited', 'emoji': '🤩', 'label': '興奮'},
    {'key': 'tired', 'emoji': '😴', 'label': '疲憊'},
    {'key': 'grateful', 'emoji': '🙏', 'label': '感恩'},
    {'key': 'confused', 'emoji': '🤔', 'label': '困惑'},
  ];

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _publishPost() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請寫下你的想法')),
      );
      return;
    }

    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請先登入才能發佈貼文')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 獲取用戶資料
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>? ?? {};

      // 獲取用戶名稱，優先順序：Firestore displayName > Firebase Auth displayName > email前綴
      String userName = userData['displayName'] ??
          FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email?.split('@')[0] ??
          '用戶';

      // 發布貼文 - 確保 authorId 正確設置
      DocumentReference postRef = await FirebaseFirestore.instance.collection('community_posts').add({
        'content': _contentController.text.trim(),
        'authorId': userId,
        'authorName': _isAnonymous ? '匿名用戶' : userName,
        'authorEmail': _isAnonymous ? null : FirebaseAuth.instance.currentUser?.email,
        'authorPhotoURL': _isAnonymous ? null : (userData['photoURL'] ?? FirebaseAuth.instance.currentUser?.photoURL),
        'mood': _selectedMood,
        'isAnonymous': _isAnonymous,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 確保文檔創建成功
      print('貼文創建成功，ID: ${postRef.id}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享成功！')),
      );

      Navigator.pop(context);
    } catch (e) {
      String errorMessage = '分享失敗';
      if (e.toString().contains('permission-denied')) {
        errorMessage = '權限不足，請檢查 Firebase 設定';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorMessage：$e')),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('分享心情'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishPost,
            child: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : Text('發布', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 心情選擇
            Text(
              '現在的心情：',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Container(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _moods.length,
                itemBuilder: (context, index) {
                  var mood = _moods[index];
                  bool isSelected = _selectedMood == mood['key'];

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMood = mood['key'];
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.only(right: 8),
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue[100] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.blue[400]! : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(mood['emoji'], style: TextStyle(fontSize: 16)),
                          SizedBox(width: 4),
                          Text(
                            mood['label'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.blue[600] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: 20),

            // 內容輸入
            Text(
              '想說什麼？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Container(
              height: MediaQuery.of(context).size.height * 0.4,
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: '分享你的感受、想法或今天發生的事...\n\n這裡是一個安全的空間，你可以自由表達自己的情感。',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.all(16),
                ),
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),

            SizedBox(height: 16),

            // 匿名選項
            Row(
              children: [
                Checkbox(
                  value: _isAnonymous,
                  onChanged: (value) {
                    setState(() {
                      _isAnonymous = value ?? false;
                    });
                  },
                ),
                Text('匿名分享'),
                Spacer(),
                Text(
                  '${_contentController.text.length}/1000',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),

            SizedBox(height: 8),

            // 提示文字
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[600], size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '記住：這裡是一個相互支持的社群，請保持善意和尊重。',
                      style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// 貼文評論頁面
class PostCommentsPage extends StatefulWidget {
  final String postId;

  const PostCommentsPage({Key? key, required this.postId}) : super(key: key);

  @override
  _PostCommentsPageState createState() => _PostCommentsPageState();
}

class _PostCommentsPageState extends State<PostCommentsPage> {
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請先登入才能評論')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 獲取用戶資料
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>? ?? {};

      // 獲取用戶名稱
      String userName = userData['displayName'] ??
          FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email?.split('@')[0] ??
          '用戶';

      print('準備添加評論，用戶: $userName');

      // 添加評論
      DocumentReference commentRef = await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
        'content': _commentController.text.trim(),
        'authorId': userId,
        'authorName': userName,
        'authorEmail': FirebaseAuth.instance.currentUser?.email,
        'authorPhotoURL': userData['photoURL'] ?? FirebaseAuth.instance.currentUser?.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('評論添加成功，ID: ${commentRef.id}');

      _commentController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回覆已發送')),
      );
    } catch (e) {
      print('評論失敗: $e');
      String errorMessage = '回覆失敗';
      if (e.toString().contains('permission-denied')) {
        errorMessage = '權限不足，請檢查 Firebase 設定';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorMessage，請稍後再試')),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('回覆'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 評論列表
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('community_posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                        SizedBox(height: 16),
                        Text('載入錯誤', style: TextStyle(fontSize: 16)),
                        SizedBox(height: 8),
                        Text('請檢查網路連接', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  );
                }

                var comments = snapshot.data?.docs ?? [];

                // 在客戶端排序（按時間正序）
                comments.sort((a, b) {
                  var aData = a.data() as Map<String, dynamic>;
                  var bData = b.data() as Map<String, dynamic>;
                  var aTime = aData['createdAt'] as Timestamp?;
                  var bTime = bData['createdAt'] as Timestamp?;
                  if (aTime == null || bTime == null) return 0;
                  return aTime.compareTo(bTime);
                });

                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.comment_outlined, size: 48, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '還沒有人回覆',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '成為第一個回覆的人',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    var comment = comments[index].data() as Map<String, dynamic>;
                    return CommentCard(comment: comment);
                  },
                );
              },
            ),
          ),

          // 評論輸入框
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: '寫下你的回覆...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _addComment(),
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: _isLoading ? null : _addComment,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      shape: BoxShape.circle,
                    ),
                    child: _isLoading
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 評論卡片
class CommentCard extends StatelessWidget {
  final Map<String, dynamic> comment;

  const CommentCard({Key? key, required this.comment}) : super(key: key);

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '剛剛';

    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();
    Duration difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    String authorName = comment['authorName'] ?? '用戶';

    // 如果顯示名稱為 '未知用戶'，嘗試從 email 中提取用戶名
    if (authorName == '未知用戶' && comment['authorEmail'] != null) {
      authorName = comment['authorEmail'].split('@')[0];
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue[100],
                child: comment['authorPhotoURL'] != null
                    ? null
                    : Icon(Icons.person, color: Colors.blue[600], size: 16),
                backgroundImage: comment['authorPhotoURL'] != null
                    ? NetworkImage(comment['authorPhotoURL'])
                    : null,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _formatTimestamp(comment['createdAt']),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            comment['content'] ?? '',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// 以下是原有的其他頁面，保持不變
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

    int newExp = currentExp + 5;
    int newHappiness = (currentHappiness + 3).clamp(0, 100);
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