import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:esewa_flutter_sdk/esewa_flutter_sdk.dart';
import 'package:esewa_flutter_sdk/esewa_config.dart';
import 'package:esewa_flutter_sdk/esewa_payment.dart';
import 'package:esewa_flutter_sdk/esewa_payment_success_result.dart';


class EsewaService {
  // Standard Sandbox Credentials for Native SDK
  static const String _clientId = "JB0BBQ4aD0UqIThFJwAKBgAXEUkEGQUBBAwdOgABHD4DChwUAB0R";
  static const String _secretKey = "BhwIWQQADhIYSxILExMcAgFXFhcOBwAKBgAXEQ==";

  static void initiatePayment({
    required String productId,
    required String productName,
    required String amount,
    required VoidCallback onSuccess,
    required Function(String) onFailure,
  }) {
    try {
      EsewaFlutterSdk.initPayment(
        esewaConfig: EsewaConfig(
          environment: Environment.test,
          clientId: _clientId,
          secretId: _secretKey,
        ),
        esewaPayment: EsewaPayment(
          productId: productId,
          productName: productName,
          productPrice: amount,
          callbackUrl: "https://example.com/callback", // Dummy URL for sandbox
        ),
        onPaymentSuccess: (EsewaPaymentSuccessResult data) {
          debugPrint(":::ESEWA SUCCESS::: => ${data.toJson()}");
          _verifyTransactionStatus(data, onSuccess, onFailure);
        },
        onPaymentFailure: (data) {
          debugPrint(":::ESEWA FAILURE::: => $data");
          onFailure("Payment Failed or Cancelled");
        },
        onPaymentCancellation: (data) {
          debugPrint(":::ESEWA CANCELLATION::: => $data");
          onFailure("Payment Cancelled");
        },
      );
    } on Exception catch (e) {
      debugPrint("ESEWA EXCEPTION : ${e.toString()}");
      onFailure(e.toString());
    }
  }

  static Future<void> _verifyTransactionStatus(
    EsewaPaymentSuccessResult result,
    VoidCallback onSuccess,
    Function(String) onFailure,
  ) async {
    try {
      final url = Uri.parse("https://rc.esewa.com.np/mobile/transaction?txnRefId=${result.refId}");
      
      final response = await http.get(
        url,
        headers: {
          'merchantId': _clientId,
          'merchantSecret': _secretKey,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseData = jsonDecode(response.body);
        if (responseData.isNotEmpty) {
          final status = responseData[0]['transactionDetails']['status'];
          if (status == 'COMPLETE') {
            onSuccess();
            return;
          }
        }
        onFailure("Transaction verification failed: Status not COMPLETE.");
      } else {
        onFailure("Transaction verification failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Verification Error: $e");
      onFailure("Error verifying transaction: ${e.toString()}");
    }
  }
}
