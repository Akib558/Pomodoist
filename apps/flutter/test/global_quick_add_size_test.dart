import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';

void main() {
  test(
    'voice takes priority and closing it restores the open comment size',
    () {
      expect(
        globalQuickAddWindowSize(voiceExpanded: true, commentExpanded: true),
        globalQuickAddVoiceSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: false, commentExpanded: true),
        globalQuickAddCommentSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: false, commentExpanded: false),
        globalQuickAddCompactSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: true, commentExpanded: false),
        globalQuickAddVoiceSize,
      );
    },
  );
}
