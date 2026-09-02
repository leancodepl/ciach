/// Client entrypoint: hydrates the `@client` islands on the pre-rendered page.
library;

import 'package:ciach_website/main.client.options.dart';
import 'package:jaspr/client.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);
  runApp(const ClientApp());
}
