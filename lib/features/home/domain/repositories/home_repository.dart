import '../entities/restaurant.dart';

abstract class HomeRepository {
  Future<List<Restaurant>> getRestaurants();
}
