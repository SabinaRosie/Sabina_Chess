import 'package:flutter/material.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Grandmaster Dashboard"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Welcome back, Grandmaster!",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // 🔹 Game Description Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text("♟️", style: TextStyle(fontSize: 30)),
                          SizedBox(width: 10),
                          Text(
                            "The Ultimate Challenge",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Chess is a game of strategy and precision. Whether you are a beginner or a seasoned pro, every move counts. Challenge your mind, anticipate your opponent, and claim your victory.",
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // 🔹 Play Button
              Center(
                child: Column(
                  children: [
                    const Text(
                      "Ready to make your move?",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () {
                          RouteGenerator.navigateToPage(
                            context,
                            Routes.gameRoute,
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 30),
                        label: const Text(
                          "START PLAYING CHESS",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 🔹 Stats Preview Placeholder
              const Text(
                "Recent Activity",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const ListTile(
                leading: CircleAvatar(child: Icon(Icons.history)),
                title: Text("Last Match: Won"),
                subtitle: Text("Against Stockfish Level 3"),
                trailing: Text("2h ago"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
