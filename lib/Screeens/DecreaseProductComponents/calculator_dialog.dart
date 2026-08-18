import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void showCalculatorDialog(BuildContext context) {
  String exprStr = '';
  String displayStr = '0';

  double evalExpr(String expr) {
    // Replace display symbols
    expr = expr.replaceAll('×', '*').replaceAll('÷', '/');
    // Split into tokens
    final List<String> tokens = [];
    String numStr = '';
    for (int i = 0; i < expr.length; i++) {
      final c = expr[i];
      if ('+-*/'.contains(c)) {
        if (numStr.isNotEmpty) {
          tokens.add(numStr);
          numStr = '';
        }
        tokens.add(c);
      } else {
        numStr += c;
      }
    }
    if (numStr.isNotEmpty) tokens.add(numStr);

    if (tokens.isEmpty) return 0.0;

    // Evaluate * and / first
    List<String> t = List.from(tokens);
    for (int i = 1; i < t.length - 1; i += 2) {
      if (t[i] == '*' || t[i] == '/') {
        double a = double.parse(t[i - 1]);
        double b = double.parse(t[i + 1]);
        double r = t[i] == '*' ? a * b : a / b;
        t.replaceRange(i - 1, i + 2, [r.toString()]);
        i -= 2;
      }
    }
    // Then + and -
    if (t.isEmpty) return 0.0;
    double result = double.tryParse(t[0]) ?? 0.0;
    for (int i = 1; i < t.length - 1; i += 2) {
      double b = double.parse(t[i + 1]);
      if (t[i] == '+') result += b;
      if (t[i] == '-') result -= b;
    }
    return result;
  }

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setCalc) {
        void press(String val) {
          setCalc(() {
            if (val == 'C') {
              exprStr = '';
              displayStr = '0';
            } else if (val == '=') {
              try {
                // Simple evaluator via Dart double arithmetic
                final result = evalExpr(exprStr);
                displayStr = result
                    .toStringAsFixed(2)
                    .replaceAll(RegExp(r'\.?0+$'), '');
                exprStr = displayStr;
              } catch (_) {
                displayStr = 'خطأ';
                exprStr = '';
              }
            } else if (val == '⌫') {
              if (exprStr.isNotEmpty) {
                exprStr = exprStr.substring(0, exprStr.length - 1);
                displayStr = exprStr.isEmpty ? '0' : exprStr;
              }
            } else {
              exprStr += val;
              displayStr = exprStr;
            }
          });
        }

        Widget buildBtn(String label,
            {Color bg = const Color(0xfff0f0f0), Color fg = Colors.black87}) {
          return Expanded(
            child: GestureDetector(
              onTap: () => press(label),
              child: Container(
                margin: EdgeInsets.all(3.w),
                padding: EdgeInsets.symmetric(vertical: 14.h),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: fg)),
                ),
              ),
            ),
          );
        }

        return Directionality(
          textDirection: TextDirection.ltr,
          child: AlertDialog(
            title: Text('الحاسبة',
                textAlign: TextAlign.right,
                style:
                    TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            content: SizedBox(
              width: 280.w,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(displayStr,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 26.sp, fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 10.h),
                Row(children: [
                  buildBtn('7'),
                  buildBtn('8'),
                  buildBtn('9'),
                  buildBtn('÷',
                      bg: Colors.orange.shade100, fg: Colors.orange.shade800),
                ]),
                Row(children: [
                  buildBtn('4'),
                  buildBtn('5'),
                  buildBtn('6'),
                  buildBtn('×',
                      bg: Colors.orange.shade100, fg: Colors.orange.shade800),
                ]),
                Row(children: [
                  buildBtn('1'),
                  buildBtn('2'),
                  buildBtn('3'),
                  buildBtn('-',
                      bg: Colors.orange.shade100, fg: Colors.orange.shade800),
                ]),
                Row(children: [
                  buildBtn('0'),
                  buildBtn('.'),
                  buildBtn('⌫', bg: Colors.red.shade50, fg: Colors.red),
                  buildBtn('+',
                      bg: Colors.orange.shade100, fg: Colors.orange.shade800),
                ]),
                Row(children: [
                  buildBtn('C', bg: Colors.grey.shade300, fg: Colors.black87),
                  buildBtn('=',
                      bg: Colors.orange.withOpacity(0.85), fg: Colors.white),
                ]),
              ]),
            ),
          ),
        );
      });
    },
  );
}
