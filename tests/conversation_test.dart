import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maalish_app/models/chat_message.dart';
import 'package:maalish_app/models/conversation.dart';
import 'package:maalish_app/services/conversation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Conversation sample(String id) {
    final time = DateTime.utc(2026,10,23,12);
    return Conversation(id: id, title: 'موضوع قديم', preview: 'رسالة',
      summary: 'سياق مستمر', createdAt: time, lastMessageAt: time,
      messages: [SavedMessage('message1',ChatMessage(text: 'كلام محفوظ', fromUser: true, createdAt: time))]);
  }
  test('transcript, roles, timestamps and rolling summary survive restart', () async {
    final service = ConversationService(); final value = sample(service.newId());
    await service.store(value,value.messages);
    final restored = await ConversationService().open(value.id);
    expect(restored.messages.single.message.text,'كلام محفوظ');
    expect(restored.messages.single.message.fromUser,isTrue);
    expect(restored.messages.single.message.createdAt,value.createdAt);
    expect(restored.summary,'سياق مستمر');
    expect(restored.id,value.id);
    expect(await service.pending(value.id),isTrue);
  });
  test('resuming updates same conversation and preserves original messages', () async {
    final service = ConversationService(); final first = sample(service.newId());
    await service.store(first,first.messages);
    final next = SavedMessage('message2',ChatMessage(text: 'تكملة',fromUser: false));
    await service.store(first.copyWith(messages:[...first.messages,next]),[next]);
    expect((await service.listLocal()).length,1);
    expect((await service.open(first.id)).messages.length,2);
  });
  test('deleting one chat clears its private content, preserves other chats and outbox', () async {
    final service = ConversationService(); final first = sample(service.newId()), second = sample(service.newId());
    await service.store(first,first.messages); await service.store(second,second.messages);
    await service.delete(first);
    expect((await service.listLocal()).single.id,second.id);
    final tombstone = await service.local(first.id);
    expect(tombstone!.messages,isEmpty); expect(tombstone.summary,isEmpty);
    expect(tombstone.title,isEmpty); expect(tombstone.preview,isEmpty);
    expect(await service.pending(first.id),isTrue);
    await expectLater(service.open(first.id),throwsStateError);
  });
  test('new storage retains more than fifty conversations', () async {
    final service = ConversationService();
    for(var i=0;i<55;i++) { final value=sample('chat$i'); await service.store(value,value.messages); }
    expect((await service.listLocal()).length,55);
  });
}
