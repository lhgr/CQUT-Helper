import '../lib/utils/ios_release.dart';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(arguments.single)) {
    throw ArgumentError('Provide a numeric version in x.y.z format');
  }
  print('ipa_filename=${currentIosRelease.ipaFileName(arguments.single)}');
}
