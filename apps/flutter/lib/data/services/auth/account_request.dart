import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

Future<T> accountRequest<T>(
  AccountClient account,
  Future<T> Function() request,
) async {
  final token = account.currentSession?.accessToken;
  try {
    return await request();
  } on PostgrestException catch (error) {
    if (error.code == 'PT401' &&
        token != null &&
        account.currentSession?.accessToken == token) {
      try {
        await account.signOut();
      } on Object {
        // GoTrue clears the local session before sending logout. Preserve the
        // original rejection if that advisory network request fails.
      }
    }
    rethrow;
  }
}
