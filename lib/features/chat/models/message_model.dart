enum MessageType {
  text,
  image,
  file,
  emoji,
}

class Message {
  final String id;
  final String text;
  final DateTime timestamp;
  final bool isSender;
  final bool isRead;
  final MessageType type;
  final String? attachmentUrl;
  final String? attachmentName;

  const Message({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.isSender,
    this.isRead = true,
    this.type = MessageType.text,
    this.attachmentUrl,
    this.attachmentName,
  });
}
