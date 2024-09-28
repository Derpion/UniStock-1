import 'package:UNISTOCK/models/CartItem.dart';
import 'package:UNISTOCK/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class CartPage extends StatefulWidget {
  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late Stream<List<CartItem>> cartItemsStream;
  StreamSubscription<List<CartItem>>? cartItemsSubscription;
  Set<int> selectedItems = {};
  bool selectAll = false;
  List<CartItem> cartItems = [];
  late NotificationService notificationService;

  @override
  void initState() {
    super.initState();
    notificationService = NotificationService();
    final FirebaseAuth auth = FirebaseAuth.instance;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final User? user = auth.currentUser;

    if (user != null) {
      cartItemsStream = firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .snapshots()
          .map((snapshot) => _aggregateCartItems(snapshot.docs))
          .cast<List<CartItem>>();

      cartItemsSubscription = cartItemsStream.listen((items) {
        if (mounted) {
          setState(() {
            cartItems = items;

            if (selectAll) {
              selectedItems = cartItems.map((item) => item.id.hashCode).toSet();
            } else {
              selectedItems = cartItems
                  .where((item) => item.selected)
                  .map((item) => item.id.hashCode)
                  .toSet();
            }
          });
        }
      });
    } else {
      cartItemsStream = Stream.value([]);
    }
  }

  List<CartItem> _aggregateCartItems(List<DocumentSnapshot> docs) {
    Map<String, CartItem> groupedItems = {};

    for (var doc in docs) {
      CartItem item = CartItem.fromFirestore(doc);
      String uniqueKey = "${item.itemLabel}_${item.selectedSize}";

      if (groupedItems.containsKey(uniqueKey)) {
        groupedItems[uniqueKey]!.quantity += item.quantity;
        groupedItems[uniqueKey]!.documentReferences.add(doc.reference);
      } else {
        groupedItems[uniqueKey] = CartItem(
          id: item.id,
          itemLabel: item.itemLabel,
          imagePath: item.imagePath,
          availableSizes: item.availableSizes,
          selectedSize: item.selectedSize,
          price: item.price,
          quantity: item.quantity,
          selected: item.selected,
          category: item.category,
          courseLabel: item.courseLabel,
          documentReferences: [doc.reference], // Store DocumentReference objects
        );
      }
    }

    return groupedItems.values.toList();
  }

  @override
  void dispose() {
    cartItemsSubscription?.cancel();
    super.dispose();
  }

  Future<void> updateCartItemQuantity(String itemLabel, int change) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final User? user = auth.currentUser;

    if (user != null) {
      final cartDocs = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .where('itemLabel', isEqualTo: itemLabel)
          .get();

      int totalQuantity =
      cartDocs.docs.fold(0, (sum, doc) => sum + (doc['quantity'] as int));

      totalQuantity += change;

      if (totalQuantity > 0) {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('cart')
            .doc(cartDocs.docs[0].id)
            .update({'quantity': totalQuantity});

        for (var i = 1; i < cartDocs.docs.length; i++) {
          await firestore
              .collection('users')
              .doc(user.uid)
              .collection('cart')
              .doc(cartDocs.docs[i].id)
              .delete();
        }

        setState(() {
          cartItems = cartItems
              .where((item) => item.itemLabel != itemLabel || totalQuantity > 0)
              .toList();
        });
      } else {
        for (var doc in cartDocs.docs) {
          await firestore
              .collection('users')
              .doc(user.uid)
              .collection('cart')
              .doc(doc.id)
              .delete();
        }

        setState(() {
          cartItems =
              cartItems.where((item) => item.itemLabel != itemLabel).toList();
        });
      }
    }
  }

  Future<void> updateCartItemSelection(List<DocumentReference> docRefs, bool? selected) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final WriteBatch batch = firestore.batch();

    for (DocumentReference docRef in docRefs) {
      batch.update(docRef, {'selected': selected});
    }

    await batch.commit();
  }

  void handleCheckboxChanged(bool? value, CartItem item) {
    if (mounted) {
      setState(() {
        if (value == true) {
          selectedItems.add(item.id.hashCode);
        } else {
          selectedItems.remove(item.id.hashCode);
        }

        // Update all aggregated documents for this item
        updateCartItemSelection(item.documentReferences, value);
      });
    }
  }

  void handleSelectAllChanged(bool? value) {
    if (mounted) {
      setState(() {
        selectAll = value ?? false;
        for (var item in cartItems) {
          handleCheckboxChanged(selectAll, item);
        }
      });
    }
  }

  void handleQuantityChanged(String itemLabel, String? itemSize, int change) async {
    await updateCartItemQuantity(itemLabel, change);
  }

  void showTermsAndConditionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Terms and Conditions'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: SingleChildScrollView(
              child: Text(
                '1. Acceptance of Terms: By accessing or using this service, you agree to be bound by these terms and conditions. If you do not agree with any part of these terms, you may not use the service.\n\n'
                    '2. Use of Service: The service provided is for personal and non-commercial use only. You agree not to modify, copy, distribute, transmit, display, perform, reproduce, publish, license, create derivative works from, transfer, or sell any information, software, products, or services obtained from the service.\n\n'
                    '3. User Responsibilities: You are responsible for maintaining the confidentiality of any account information and passwords used for this service. You agree to accept responsibility for all activities that occur under your account or password.\n\n'
                    '4. Privacy: Your use of the service is subject to our Privacy Policy, which governs the collection, use, and disclosure of your information. By using the service, you consent to the practices described in the Privacy Policy.\n\n'
                    '5. Limitation of Liability: In no event shall we be liable for any direct, indirect, incidental, special, consequential, or punitive damages arising out of or related to your use of the service, whether based on warranty, contract, tort (including negligence), or any other legal theory.\n\n'
                    '6. Indemnification: You agree to indemnify and hold harmless the service provider, its affiliates, officers, directors, employees, and agents from and against any claims, liabilities, damages, losses, and expenses, including without limitation reasonable legal and accounting fees, arising out of or in any way connected with your access to or use of the service or your violation of these terms.\n\n'
                    '7. Modification of Terms: We reserve the right to modify or revise these terms and conditions at any time without prior notice. By continuing to use the service after such modifications, you agree to be bound by the revised terms.\n\n'
                    '8. Governing Law: These terms and conditions shall be governed by and construed in accordance with the laws of [Jurisdiction], without regard to its conflict of law provisions.\n\n'
                    '9. Contact: If you have any questions or concerns about these terms and conditions, please contact us at [Contact Information].',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Deny'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Accept'),
              onPressed: () async {
                Navigator.of(context).pop();
                handleCheckout();
              },
            ),
          ],
        );
      },
    );
  }

  void handleCheckout() async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final User? user = auth.currentUser;

    if (user != null) {
      final cartCollection = firestore.collection('users').doc(user.uid).collection('cart');
      final ordersCollection = firestore.collection('users').doc(user.uid).collection('orders');
      final WriteBatch batch = firestore.batch();

      for (CartItem item in cartItems) {
        if (item.selected) {
          for (DocumentReference cartDocRef in item.documentReferences) {
            batch.update(cartDocRef, {'status': 'bought'});
            batch.delete(cartDocRef);

            final orderDocRef = ordersCollection.doc();
            batch.set(orderDocRef, {
              'itemLabel': item.itemLabel,
              'itemSize': item.selectedSize ?? '',
              'imagePath': item.imagePath,
              'price': item.price,
              'quantity': item.quantity,
              'orderDate': FieldValue.serverTimestamp(),
              'category': item.category,
              'courseLabel': item.courseLabel,
            });

            await notificationService.showNotification(
              user.uid,
              item.itemLabel.hashCode,
              'Item Purchased',
              'Your purchase for ${item.itemLabel} has been successfully processed.',
            );
          }
        }
      }

      try {
        await batch.commit();
        print("Checked out items successfully and removed from cart.");
      } catch (e) {
        print("Failed to complete batch operation: $e");
      }
    } else {
      print("User not logged in");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cart'),
        backgroundColor: Color(0xFF046be0),
      ),
      body: StreamBuilder<List<CartItem>>(
        stream: cartItemsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No items in the cart.'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: selectAll,
                      onChanged: handleSelectAllChanged,
                    ),
                    Text(
                      'Select All',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: cartItems.length,
                  itemBuilder: (context, index) {
                    return buildCartItem(cartItems[index]);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: () {
                    showTermsAndConditionsDialog(context);
                  },
                  child: Text('Checkout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFFEB3B),
                    padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    textStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget buildCartItem(CartItem item) {
    final int totalPrice = item.price * item.quantity;

    return Card(
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Checkbox(
                value: selectedItems.contains(item.id.hashCode),
                onChanged: (bool? value) {
                  handleCheckboxChanged(value, item);
                },
              ),
            ),
            SizedBox(
              width: 50,
              height: 50,
              child: Image.network(
                item.imagePath,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Size: ${item.selectedSize ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₱$totalPrice',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.remove),
                            onPressed: item.quantity > 1
                                ? () {
                              handleQuantityChanged(item.itemLabel, item.selectedSize, -1);
                            }
                                : null,
                          ),
                          Text('${item.quantity}'),
                          IconButton(
                            icon: Icon(Icons.add),
                            onPressed: () {
                              handleQuantityChanged(item.itemLabel, item.selectedSize, 1);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
