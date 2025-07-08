import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/openai_service.dart';


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

  // 修改頁面列表，添加聊天機器人頁面
  final List<Widget> _pages = [
    IntegratedGrowthPage(),
    MoodRecordPage(),
    AIChatBotPage(),  // 新增聊天機器人頁面
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
              icon: Icon(Icons.smart_toy),
              activeIcon: Icon(Icons.smart_toy, size: 28),
              label: '心靈陪伴',
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

// 資源教育頁面 - 簡化版本，移除互動功能
class EducationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '資源教育中心',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 10),
          Text(
            '關注心理健康，提升生活品質',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _buildEducationCard(
                  context,
                  '認識憂鬱症',
                  '了解憂鬱症的症狀和成因',
                  '🧠',
                  Colors.blue,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DepressionEducationPage()),
                  ),
                ),
                _buildEducationCard(
                  context,
                  '情緒管理技巧',
                  '學習有效的情緒調節方法',
                  '😊',
                  Colors.green,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EmotionManagementPage()),
                  ),
                ),
                _buildEducationCard(
                  context,
                  '睡眠健康',
                  '改善睡眠品質的方法',
                  '🌙',
                  Colors.purple,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SleepHealthPage()),
                  ),
                ),
                _buildEducationCard(
                  context,
                  '人際關係',
                  '建立健康的人際互動',
                  '👥',
                  Colors.orange,
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RelationshipPage()),
                  ),
                ),
              ],
            ),
          ),
          // 緊急聯絡區域
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            margin: EdgeInsets.only(top: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red[400]!, Colors.red[600]!],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Text(
                  '需要立即協助嗎？',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '如果您正面臨心理危機或有自殺念頭，請立即尋求專業幫助',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () => _showEmergencyContacts(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red[600],
                  ),
                  child: Text('緊急聯絡資訊'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEducationCard(
      BuildContext context,
      String title,
      String subtitle,
      String emoji,
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
                textAlign: TextAlign.center,
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

  void _showEmergencyContacts(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red),
            SizedBox(width: 8),
            Text('緊急聯絡資訊', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🆘 24小時專線服務', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 15),
              _buildEmergencyContact('生命線協談專線', '1995', context),
              _buildEmergencyContact('張老師專線', '1980', context),
              _buildEmergencyContact('安心專線', '1925', context),
              _buildEmergencyContact('緊急救護', '119', context),
              _buildEmergencyContact('報警專線', '110', context),
              SizedBox(height: 15),
              Text('💡 網路資源', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 衛生福利部心理健康司\n• 台灣自殺防治學會\n• 董氏基金會心理衛生中心\n• 各縣市心理衛生中心'),
              SizedBox(height: 15),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠️ 如有立即生命危險，請撥打 110 或 119。尋求專業幫助是勇敢的表現，您並不孤單。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContact(String title, String number, BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title)),
          GestureDetector(
            onTap: () {
              // 這裡可以整合撥號功能
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('撥號: $number')),
              );
            },
            child: Text(
              number,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 認識憂鬱症頁面 - 簡化版本
class DepressionEducationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        title: Text('認識憂鬱症'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              '什麼是憂鬱症？',
              '憂鬱症是一種常見的心理疾病，會影響一個人的感受、思考和行為方式。它不僅僅是暫時的情緒低落，而是一種持續的狀態，會干擾日常生活和工作。\n\n憂鬱症影響全球超過2.8億人，是導致殘疾的主要原因之一。重要的是要知道，憂鬱症是可以治療的。',
              Icons.psychology,
              Colors.blue,
            ),
            _buildSectionCard(
              '常見症狀',
              '憂鬱症的症狀可能因人而異，但通常包括以下幾個方面。如果這些症狀持續兩週以上，建議尋求專業協助：',
              Icons.checklist,
              Colors.orange,
              symptoms: [
                '持續的悲傷、空虛感或絕望感',
                '對日常活動失去興趣或快樂感',
                '睡眠問題（失眠或過度睡眠）',
                '食慾或體重的顯著變化',
                '疲勞和精力不足',
                '難以集中注意力、記憶或做決定',
                '自我價值感低落或過度自責',
                '身體不適（頭痛、消化問題等）',
                '自殺或死亡的念頭'
              ],
            ),
            _buildSectionCard(
              '可能的成因',
              '憂鬱症的成因複雜，通常是多種因素共同作用的結果：',
              Icons.psychology,
              Colors.green,
              symptoms: [
                '生物因素：遺傳傾向、大腦化學物質失衡、荷爾蒙變化',
                '心理因素：創傷經歷、長期壓力、負面思維模式',
                '環境因素：生活變故、人際關係問題、經濟困難',
                '醫學因素：某些疾病、藥物副作用、物質濫用',
                '社會因素：孤立感、缺乏社會支持、歧視經歷'
              ],
            ),
            _buildSectionCard(
              '治療方法',
              '憂鬱症是可以有效治療的。常見的治療方法包括：',
              Icons.healing,
              Colors.purple,
              symptoms: [
                '心理治療：認知行為治療(CBT)、人際治療、心理動力治療',
                '藥物治療：抗憂鬱藥物（需在醫師指導下使用）',
                '生活方式調整：規律運動、健康飲食、充足睡眠',
                '社會支持：家人朋友的陪伴、支持小組',
                '專業諮詢：心理師、精神科醫師、社工師',
                '替代療法：藝術治療、音樂治療、正念冥想'
              ],
            ),
            _buildSectionCard(
              '何時尋求幫助',
              '如果您或您關心的人出現以下情況，請立即尋求專業幫助：',
              Icons.warning,
              Colors.red,
              symptoms: [
                '症狀持續兩週以上且影響日常生活',
                '有自殺或自傷的想法',
                '無法照顧自己的基本需求',
                '出現幻覺或妄想',
                '家人朋友表達擔憂'
              ],
            ),
            SizedBox(height: 20),
            // 專業協助資源
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone, color: Colors.blue[800]),
                      SizedBox(width: 8),
                      Text(
                        '專業協助資源',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 15),
                  Text('🏥 醫療機構：', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('• 精神科門診\n• 心理師諮詢\n• 心理衛生中心'),
                  SizedBox(height: 10),
                  Text('📞 專線服務：', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('• 1925 安心專線\n• 1995 生命線\n• 1980 張老師'),
                  SizedBox(height: 10),
                  Text('💡 溫馨提醒：', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('尋求專業幫助是勇敢的表現，不要害怕踏出第一步。治療越早開始，康復的機會越大。'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, String? description, IconData icon, Color color, {List<String>? symptoms}) {
    return Card(
      margin: EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              SizedBox(height: 15),
              Text(description, style: TextStyle(fontSize: 16, height: 1.5)),
            ],
            if (symptoms != null) ...[
              SizedBox(height: 15),
              ...symptoms.map((symptom) => Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                    Expanded(child: Text(symptom, style: TextStyle(fontSize: 14, height: 1.4))),
                  ],
                ),
              )).toList(),
            ],
          ],
        ),
      ),
    );
  }
}

// 情緒管理技巧頁面 - 簡化版本
class EmotionManagementPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: Text('情緒管理技巧'),
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            _buildIntroCard(),
            _buildTechniqueCard(
              '深呼吸與放鬆技巧',
              '深呼吸是最簡單有效的情緒調節方法之一',
              Icons.air,
              Colors.teal,
              techniques: [
                '腹式呼吸：手放在腹部，吸氣時讓腹部鼓起',
                '4-7-8呼吸法：吸氣4秒，憋氣7秒，吐氣8秒',
                '正念呼吸：專注於呼吸的感覺，不評判',
                '肌肉放鬆：從頭到腳依次緊繃和放鬆肌肉',
                '冷水洗臉：刺激迷走神經，快速冷靜'
              ],
            ),
            _buildTechniqueCard(
              '認知重構技巧',
              '改變負面思維模式，建立更積極的思考方式',
              Icons.psychology,
              Colors.blue,
              techniques: [
                '識別負面思維：注意自動化的負面想法',
                '質疑想法真實性：這個想法有證據支持嗎？',
                '尋找替代觀點：還有其他角度看這件事嗎？',
                '平衡思考：既看到困難也看到機會',
                '自我對話：用鼓勵的話語代替自我批評'
              ],
            ),
            _buildTechniqueCard(
              '正念與冥想',
              '培養當下意識，接納情緒而不被其控制',
              Icons.self_improvement,
              Colors.purple,
              techniques: [
                '身體掃描：從頭到腳感受身體各部位',
                '觀察思緒：像看雲朵一樣觀察想法來去',
                '感恩練習：每天記錄3件感恩的事',
                '慈悲冥想：對自己和他人發送善意',
                '日常正念：專注於當下的活動'
              ],
            ),
            _buildTechniqueCard(
              '情緒表達與釋放',
              '健康地表達和處理情緒，避免壓抑',
              Icons.chat,
              Colors.orange,
              techniques: [
                '情緒日記：寫下感受和觸發事件',
                '與他人分享：找信任的人傾訴',
                '創意表達：繪畫、音樂、舞蹈',
                '運動釋放：跑步、瑜伽、游泳',
                '大聲呼喊：在安全的地方釋放壓力'
              ],
            ),
            _buildTechniqueCard(
              '建立支持系統',
              '培養健康的人際關係和社會連結',
              Icons.people,
              Colors.pink,
              techniques: [
                '維持友誼：定期聯繫關心的人',
                '參加團體：興趣小組、志工活動',
                '專業支持：心理師、支持小組',
                '設定界限：學會說不，保護自己',
                '尋求幫助：不要害怕向他人求助'
              ],
            ),
            SizedBox(height: 20),
            // 實用提醒
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.green[800]),
                      SizedBox(width: 8),
                      Text(
                        '實用提醒',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text('• 情緒管理需要持續練習，不要期待立即見效'),
                  Text('• 選擇適合自己的技巧，不是所有方法都適用'),
                  Text('• 在平靜時練習技巧，緊急時才能有效運用'),
                  Text('• 如果情緒持續困擾生活，請尋求專業協助'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Card(
      margin: EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green[600],
                  child: Icon(Icons.info, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '情緒管理的重要性',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text(
              '良好的情緒管理能力有助於：\n\n• 減少壓力和焦慮\n• 改善人際關係\n• 提升工作表現\n• 增進身心健康\n• 提高生活滿意度',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechniqueCard(String title, String description, IconData icon, Color color, {required List<String> techniques}) {
    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text(description, style: TextStyle(fontSize: 16, height: 1.5)),
            SizedBox(height: 15),
            ...techniques.map((technique) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(technique, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
}

// 睡眠健康頁面 - 簡化版本
class SleepHealthPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.purple[50],
      appBar: AppBar(
        title: Text('睡眠健康'),
        backgroundColor: Colors.purple[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInfoCard(
              '睡眠的重要性',
              '充足的睡眠對身心健康至關重要。睡眠不僅能恢復體力，還對情緒穩定、記憶力提升、免疫系統強化和創造力發揮起著關鍵作用。\n\n成人每晚需要7-9小時的睡眠，但品質比時間更重要。良好的睡眠能幫助大腦清除毒素，鞏固記憶，調節情緒。',
              Icons.info_outline,
              Colors.blue,
            ),
            _buildHabitsCard(),
            _buildEnvironmentCard(),
            _buildBedtimeRoutineCard(),
            _buildAvoidCard(),
            _buildSleepProblemCard(),
            SizedBox(height: 20),
            // 睡眠改善提醒
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.purple[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates, color: Colors.purple[800]),
                      SizedBox(width: 8),
                      Text(
                        '睡眠改善小貼士',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text('• 建立規律的睡眠時間表是改善睡眠的第一步'),
                  Text('• 睡眠環境的改善比使用助眠產品更有效'),
                  Text('• 如果睡眠問題持續，請諮詢專業醫師'),
                  Text('• 避免白天長時間補眠，會影響夜間睡眠'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String content, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text(content, style: TextStyle(fontSize: 16, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitsCard() {
    final habits = [
      '每天同一時間上床睡覺和起床（包括週末）',
      '睡前2-3小時避免大量進食',
      '避免睡前4-6小時攝取咖啡因',
      '白天保持適度的自然光照射',
      '定期運動，但避免睡前3小時內激烈運動',
      '限制白天小睡時間（不超過30分鐘）'
    ];

    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.bedtime, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '睡眠衛生習慣',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text('培養良好的睡眠習慣是高品質睡眠的基礎：', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            ...habits.map((habit) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(habit, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentCard() {
    final environment = [
      '保持房間涼爽（16-19°C為理想溫度）',
      '確保房間黑暗（使用遮光窗簾）',
      '維持安靜環境（必要時使用耳塞）',
      '選擇舒適的床墊和枕頭',
      '保持房間通風良好',
      '移除電子設備或調為靜音模式'
    ];

    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: Icon(Icons.home, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '睡眠環境優化',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text('良好的睡眠環境能幫助身體自然進入睡眠狀態：', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            ...environment.map((env) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(env, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildBedtimeRoutineCard() {
    final routine = [
      '睡前1小時停止使用電子設備',
      '進行放鬆活動：閱讀、聽輕音樂',
      '溫水泡澡或淋浴',
      '練習深呼吸或冥想',
      '寫日記或感恩清單',
      '喝無咖啡因的草本茶（如洋甘菊茶）'
    ];

    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.spa, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '睡前放鬆程序',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text('建立固定的睡前儀式，幫助身心準備睡眠：', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            ...routine.map((item) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(item, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvoidCard() {
    final avoids = [
      '睡前2小時內大量飲水（避免夜間起床）',
      '酒精（雖然可能幫助入睡，但會影響睡眠品質）',
      '在床上工作、看電視或使用手機',
      '睡前激烈的身體或腦力活動',
      '不規律的睡眠時間',
      '白天過長的午睡（超過30分鐘）'
    ];

    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.block, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '需要避免的事項',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text('以下行為可能會干擾睡眠品質：', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            ...avoids.map((avoid) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(avoid, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepProblemCard() {
    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.warning, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '常見睡眠問題與對策',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber[800]),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text('如果出現以下睡眠問題，建議採取相應對策：', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            Text('• 難以入睡：嘗試放鬆技巧，如果20分鐘內無法入睡，起床做安靜活動'),
            SizedBox(height: 8),
            Text('• 夜間醒來：避免看時鐘，專注於呼吸或身體放鬆'),
            SizedBox(height: 8),
            Text('• 早醒：檢查是否有光線或噪音干擾，調整睡眠環境'),
            SizedBox(height: 8),
            Text('• 睡眠不深：評估壓力水平，考慮壓力管理技巧'),
            SizedBox(height: 8),
            Text('• 持續失眠：如果問題持續超過3週，建議諮詢醫師'),
          ],
        ),
      ),
    );
  }
}

// 人際關係頁面 - 簡化版本
class RelationshipPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange[50],
      appBar: AppBar(
        title: Text('人際關係'),
        backgroundColor: Colors.orange[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            _buildIntroCard(),
            _buildSkillCard(
              '有效溝通技巧',
              '良好的溝通是建立健康關係的基礎',
              Icons.chat,
              Colors.blue,
              skills: [
                '主動傾聽：專注於對方的話語，不打斷',
                '同理心：嘗試理解對方的感受和觀點',
                '使用"我"語句：表達感受而非指責',
                '非語言溝通：注意眼神接觸和身體語言',
                '確認理解：重複對方的話確保理解正確',
                '給予回饋：及時、具體、建設性的回應'
              ],
            ),
            _buildSkillCard(
              '建立信任關係',
              '信任是所有深度關係的基礎',
              Icons.handshake,
              Colors.green,
              skills: [
                '言行一致：說到做到，建立可靠形象',
                '保守秘密：尊重他人的隱私和信任',
                '承認錯誤：勇於承認並改正錯誤',
                '給予支持：在困難時期提供幫助',
                '分享想法：適當地開放自己',
                '尊重差異：接受並欣賞彼此的不同'
              ],
            ),
            _buildSkillCard(
              '處理衝突與分歧',
              '學會健康地解決人際問題',
              Icons.psychology,
              Colors.purple,
              skills: [
                '保持冷靜：避免情緒化反應',
                '專注問題：針對事件而非人格攻擊',
                '尋找共同點：找到雙方都認同的基礎',
                '妥協合作：願意讓步和尋找雙贏方案',
                '及時處理：不讓問題累積和惡化',
                '尋求幫助：必要時請第三方協助調解'
              ],
            ),
            _buildSkillCard(
              '設定健康界限',
              '保護個人空間和價值觀',
              Icons.shield,
              Colors.red,
              skills: [
                '清楚表達：明確說出自己的需求和限制',
                '學會說不：拒絕不合理要求而不感到罪惡',
                '時間管理：保護個人時間和空間',
                '價值堅持：堅守重要的原則和信念',
                '情緒界限：不承擔他人的情緒責任',
                '身體界限：保護個人的身體空間'
              ],
            ),
            _buildSkillCard(
              '培養深度連結',
              '建立有意義的人際關係',
              Icons.favorite,
              Colors.pink,
              skills: [
                '真誠相待：展現真實的自己',
                '共同興趣：分享活動和體驗',
                '情感支持：提供和接受情感幫助',
                '定期聯繫：主動維持關係',
                '創造回憶：一起經歷有意義的時刻',
                '相互成長：鼓勵彼此的個人發展'
              ],
            ),
            SizedBox(height: 20),
            // 人際關係改善提醒
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates, color: Colors.orange[800]),
                      SizedBox(width: 8),
                      Text(
                        '人際關係提醒',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text('• 建立良好關係需要時間和耐心'),
                  Text('• 質量比數量重要，專注於幾個深度關係'),
                  Text('• 每個人都有不同的溝通風格，要學會適應'),
                  Text('• 健康的關係是相互的，需要雙方共同努力'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Card(
      margin: EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange[600],
                  child: Icon(Icons.people, color: Colors.white),
                ),
                SizedBox(width: 15),
                Text(
                  '人際關係的重要性',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text(
              '良好的人際關係對心理健康至關重要：\n\n• 提供情感支持和歸屬感\n• 減少孤獨感和壓力\n• 增強自信心和自我價值\n• 促進個人成長和學習\n• 提高生活滿意度和幸福感',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCard(String title, String description, IconData icon, Color color, {required List<String> skills}) {
    return Card(
      margin: EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Text(description, style: TextStyle(fontSize: 16)),
            SizedBox(height: 15),
            ...skills.map((skill) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                  Expanded(child: Text(skill, style: TextStyle(fontSize: 14, height: 1.4))),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
}
// 2. OpenAI API 服務類
class OpenAIService {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  static const String _apiKey = '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'; // 請替換為您的API密鑰

  // 發送消息到ChatGPT
  static Future<String> sendMessage(String message, List<Map<String, String>> conversationHistory) async {
    try {
      // 構建對話歷史
      List<Map<String, String>> messages = [
        {
          'role': 'system',
          'content': '''你是一位專業、溫暖且富有同理心的心理陪伴助手。你的職責是：

1. 提供情感支持和理解
2. 使用溫和、鼓勵的語調
3. 避免提供專業醫療建議
4. 在用戶表達痛苦時給予安慰
5. 鼓勵積極思考和自我關愛
6. 適當時建議尋求專業幫助
7. 使用繁體中文回應

請記住：
- 始終保持耐心和理解
- 不評判用戶的感受
- 提供實用的情緒管理建議
- 當用戶表達自殺念頭時，強烈建議尋求專業幫助
- 保持對話溫暖且支持性'''
        },
      ];

      // 添加對話歷史（最近的10條消息）
      if (conversationHistory.length > 10) {
        messages.addAll(conversationHistory.sublist(conversationHistory.length - 10));
      } else {
        messages.addAll(conversationHistory);
      }

      // 添加當前用戶消息
      messages.add({
        'role': 'user',
        'content': message,
      });

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 500,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        print('OpenAI API Error: ${response.statusCode} - ${response.body}');
        return '抱歉，我現在無法回應。請稍後再試，或者如果您需要立即協助，請聯繫專業心理健康服務。';
      }
    } catch (e) {
      print('Error calling OpenAI API: $e');
      return '連接出現問題，請檢查網路連接後再試。如果問題持續，建議尋求專業協助。';
    }
  }
}

// 3. 聊天消息模型
class ChatMessage {
  final String id;
  final String message;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.message,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      message: json['message'],
      isUser: json['isUser'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

// ===== 主要聊天頁面 =====
class AIChatBotPage extends StatefulWidget {
  @override
  _AIChatBotPageState createState() => _AIChatBotPageState();
}

class _AIChatBotPageState extends State<AIChatBotPage> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isTyping = false;
  late AnimationController _typingController;
  late Animation<double> _typingAnimation;

  @override
  void initState() {
    super.initState();

    // 🔍 添加 API 密鑰調試檢查
    print('=== 聊天頁面 API 配置檢查 ===');
    print('API Key configured: ${ApiConfig.isApiKeyConfigured}');
    print('API Key prefix: ${ApiConfig.getOpenAiApiKey().length > 10 ? ApiConfig.getOpenAiApiKey().substring(0, 10) + "..." : "太短或無效"}');
    print('API Key 完整長度: ${ApiConfig.getOpenAiApiKey().length}');
    print('OpenAI URL: ${ApiConfig.openAiBaseUrl}');
    print('================================');

    _typingController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _typingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_typingController);

    _loadChatHistory();
    _sendWelcomeMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingController.dispose();
    super.dispose();
  }

  // 載入聊天歷史
  Future<void> _loadChatHistory() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('chat_history')
          .doc(userId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .limit(50)
          .get();

      setState(() {
        _messages = querySnapshot.docs
            .map((doc) => ChatMessage.fromJson(doc.data() as Map<String, dynamic>))
            .toList();
      });

      _scrollToBottom();
    } catch (e) {
      print('載入聊天歷史失敗: $e');
    }
  }

  // 保存消息到Firebase
  Future<void> _saveMessage(ChatMessage message) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat_history')
          .doc(userId)
          .collection('messages')
          .doc(message.id)
          .set(message.toJson());
    } catch (e) {
      print('保存消息失敗: $e');
    }
  }

  // 發送歡迎消息
  void _sendWelcomeMessage() {
    if (_messages.isEmpty) {
      final welcomeMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        message: '你好！我是你的心靈陪伴助手 🤗\n\n我在這裡傾聽你的感受，陪伴你度過困難時光。無論你想分享什麼，我都會用心聆聽並給予支持。\n\n請記住，尋求幫助是勇敢的表現。如果你正面臨嚴重的心理困擾，建議尋求專業心理健康服務。\n\n現在，告訴我你今天過得怎麼樣吧？',
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(welcomeMessage);
      });

      _saveMessage(welcomeMessage);
      _scrollToBottom();
    }
  }

  // 🔍 修復後的發送消息方法 - 添加詳細調試
  Future<void> _sendMessage() async {
    print('🚀 _sendMessage 方法被調用');

    if (_messageController.text.trim().isEmpty || _isLoading) {
      print('❌ 消息為空或正在載入中，取消發送');
      return;
    }

    final userMessageText = _messageController.text.trim();
    print('📝 用戶消息: $userMessageText');

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: userMessageText,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _isTyping = true;
    });

    _messageController.clear();
    _saveMessage(userMessage);
    _scrollToBottom();
    _typingController.repeat();

    // 構建對話歷史
    List<Map<String, String>> conversationHistory = _messages
        .where((msg) => msg.id != userMessage.id)
        .map((msg) => {
      'role': msg.isUser ? 'user' : 'assistant',
      'content': msg.message,
    })
        .toList();

    print('📚 對話歷史長度: ${conversationHistory.length}');

    try {
      // 🔍 關鍵調試點 - 調用 OpenAI 服務前
      print('🌟🌟🌟 準備調用 OpenAIService.sendMessage 🌟🌟🌟');
      print('🔑 API 密鑰狀態: ${ApiConfig.isApiKeyConfigured}');
      print('📞 即將調用 OpenAIService...');

      // ✅ 確保這裡調用的是正確的服務
      String aiResponse = await OpenAIService.sendMessage(
          userMessageText,  // 直接使用用戶消息文本
          conversationHistory
      );

      print('✅ 收到 AI 回應 (前50字符): ${aiResponse.length > 50 ? aiResponse.substring(0, 50) + "..." : aiResponse}');

      final aiMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        message: aiResponse,
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(aiMessage);
        _isLoading = false;
        _isTyping = false;
      });

      _typingController.stop();
      _saveMessage(aiMessage);
      _scrollToBottom();

    } catch (e) {
      print('❌ OpenAI 服務調用出錯: $e');
      print('❌ 錯誤類型: ${e.runtimeType}');
      print('❌ 錯誤詳情: ${e.toString()}');

      setState(() {
        _isLoading = false;
        _isTyping = false;
      });
      _typingController.stop();

      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        message: '抱歉，我現在遇到了一些技術問題。請稍後再試，或者如果你需要立即幫助，請聯繫專業心理健康服務。\n\n緊急情況請撥打：\n• 1995 生命線\n• 1925 安心專線\n\n錯誤信息：$e',
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(errorMessage);
      });

      _saveMessage(errorMessage);
      _scrollToBottom();
    }
  }

  // 滾動到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 清除聊天歷史
  Future<void> _clearChatHistory() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除聊天記錄'),
        content: Text('確定要清除所有聊天記錄嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('確定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      String? userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        try {
          // 刪除Firebase中的聊天記錄
          QuerySnapshot querySnapshot = await FirebaseFirestore.instance
              .collection('chat_history')
              .doc(userId)
              .collection('messages')
              .get();

          for (QueryDocumentSnapshot doc in querySnapshot.docs) {
            await doc.reference.delete();
          }

          setState(() {
            _messages.clear();
          });

          _sendWelcomeMessage();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('聊天記錄已清除')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清除失敗：$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // 頂部標題區域
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue[400]!, Colors.blue[600]!],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.smart_toy, color: Colors.white, size: 24),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '心靈陪伴助手',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              _isTyping ? '正在輸入...' : '隨時陪伴，用心聆聽',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 🔍 添加 API 狀態指示器
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: ApiConfig.isApiKeyConfigured
                              ? Colors.green.withOpacity(0.3)
                              : Colors.red.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          ApiConfig.isApiKeyConfigured ? 'AI 已連接' : 'AI 未配置',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.white),
                        onSelected: (value) {
                          if (value == 'clear') {
                            _clearChatHistory();
                          } else if (value == 'debug') {
                            _showDebugInfo();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'debug',
                            child: Row(
                              children: [
                                Icon(Icons.bug_report, size: 20, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('調試信息'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                Icon(Icons.clear_all, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('清除記錄'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_isTyping) ...[
                    SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _typingAnimation,
                      builder: (context, child) {
                        return Row(
                          children: [
                            SizedBox(width: 48),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ...List.generate(3, (index) {
                                    return AnimatedContainer(
                                      duration: Duration(milliseconds: 300),
                                      margin: EdgeInsets.symmetric(horizontal: 2),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(
                                            0.3 + 0.7 * (((_typingAnimation.value + index * 0.3) % 1.0))
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 聊天消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatMessageBubble(message: _messages[index]);
              },
            ),
          ),

          // 輸入區域
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: '分享你的感受...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        enabled: !_isLoading,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : _sendMessage,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isLoading ? Colors.grey[400] : Colors.blue[600],
                        shape: BoxShape.circle,
                      ),
                      child: _isLoading
                          ? SizedBox(
                        width: 20,
                        height: 20,
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
          ),
        ],
      ),
    );
  }

  // 🔍 新增：顯示調試信息
  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('調試信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('API 配置狀態:'),
              Text('• 已配置: ${ApiConfig.isApiKeyConfigured}'),
              Text('• 密鑰前綴: ${ApiConfig.getOpenAiApiKey().length > 10 ? ApiConfig.getOpenAiApiKey().substring(0, 10) + "..." : "無效"}'),
              Text('• 密鑰長度: ${ApiConfig.getOpenAiApiKey().length}'),
              Text('• API URL: ${ApiConfig.openAiBaseUrl}'),
              SizedBox(height: 10),
              Text('用戶狀態:'),
              Text('• 用戶ID: ${FirebaseAuth.instance.currentUser?.uid ?? "未登入"}'),
              Text('• 郵箱: ${FirebaseAuth.instance.currentUser?.email ?? "無"}'),
              SizedBox(height: 10),
              Text('消息統計:'),
              Text('• 當前消息數: ${_messages.length}'),
              Text('• 載入中: $_isLoading'),
              Text('• 正在輸入: $_isTyping'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('關閉'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 測試 API 調用
              _testApiCall();
            },
            child: Text('測試 API'),
          ),
        ],
      ),
    );
  }

  // 🔍 新增：測試 API 調用
  Future<void> _testApiCall() async {
    print('🧪 開始測試 API 調用...');
    try {
      String testResponse = await OpenAIService.sendMessage(
          '你好，這是一個測試消息',
          []
      );
      print('🧪 測試成功，回應: $testResponse');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('API 測試成功！'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('🧪 測試失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('API 測試失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ===== 聊天消息氣泡組件 =====
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy, color: Colors.blue[600], size: 20),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: message.isUser ? Colors.blue[600] : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.message,
                    style: TextStyle(
                      color: message.isUser ? Colors.white : Colors.black87,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.person, color: Colors.blue[600], size: 16),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小時前';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}