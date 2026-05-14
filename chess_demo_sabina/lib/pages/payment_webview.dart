import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/color_utils.dart';

class PaymentWebView extends StatefulWidget {
  final Map<String, dynamic> paymentData;
  final Function(String message) onSuccess;
  final VoidCallback onFailure;

  const PaymentWebView({
    super.key,
    required this.paymentData,
    required this.onSuccess,
    required this.onFailure,
  });

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
            _checkUrl(url);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (_checkUrl(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    _loadPaymentForm();
  }

  bool _checkUrl(String url) {
    debugPrint("WebView URL: $url");
    
    // Only trigger if the URL contains our specific success/failure markers
    // and it's NOT a data URI or local load
    if (url.startsWith("http") && url.contains("success")) {
      final uri = Uri.parse(url);
      final data = uri.queryParameters['data'];
      if (data != null && data.isNotEmpty) {
        widget.onSuccess(data);
        Navigator.pop(context);
        return true;
      }
    } else if (url.startsWith("http") && url.contains("failure")) {
      widget.onFailure();
      Navigator.pop(context);
      return true;
    }
    return false;
  }

  void _loadPaymentForm() {
    final data = widget.paymentData;
    const esewaUrl = "https://rc-epay.esewa.com.np/api/epay/main/v2/form";
    
    // Using a cleaner form without IDs, matching official docs exactly
    final html = """
      <!DOCTYPE html>
      <html>
        <head><title>eSewa</title></head>
        <body onload="document.getElementById('esewa-form').submit()">
          <form id="esewa-form" action="$esewaUrl" method="POST">
            <input type="hidden" name="amount" value="${data['amount']}">
            <input type="hidden" name="tax_amount" value="0">
            <input type="hidden" name="total_amount" value="${data['amount']}">
            <input type="hidden" name="transaction_uuid" value="${data['transaction_uuid']}">
            <input type="hidden" name="product_code" value="${data['merchant_id']}">
            <input type="hidden" name="product_service_charge" value="0">
            <input type="hidden" name="product_delivery_charge" value="0">
            <input type="hidden" name="success_url" value="https://example.com/success">
            <input type="hidden" name="failure_url" value="https://example.com/failure">
            <input type="hidden" name="signed_field_names" value="total_amount,transaction_uuid,product_code">
            <input type="hidden" name="signature" value="${data['signature']}">
          </form>
        </body>
      </html>
    """;

    _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("eSewa Checkout"),
        backgroundColor: AppColors.backgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.secondaryColor),
            ),
        ],
      ),
    );
  }
}
