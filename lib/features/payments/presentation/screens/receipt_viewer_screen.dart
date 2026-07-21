import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';

/// Fullscreen zoomable receipt viewer. Reused by both rider and vendor.
/// Download opens the public URL in the browser/OS handler (web-safe;
/// no extra file-system plugin needed).
class ReceiptViewerArgs {
  final String receiptUrl;
  final String? uploadedByName;
  final DateTime? uploadedAt;

  const ReceiptViewerArgs({required this.receiptUrl, this.uploadedByName, this.uploadedAt});
}

class ReceiptViewerScreen extends StatelessWidget {
  final ReceiptViewerArgs args;
  const ReceiptViewerScreen({super.key, required this.args});

  Future<void> _download() async {
    final uri = Uri.tryParse(args.receiptUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: _download,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  args.receiptUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, _, __) => const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
                  ),
                ),
              ),
            ),
          ),
          if (args.uploadedByName != null || args.uploadedAt != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (args.uploadedByName != null)
                    Text('Uploaded by ${args.uploadedByName}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  if (args.uploadedAt != null)
                    Text(
                      args.uploadedAt!.toLocal().toString().split('.').first,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
