extends TestSupport
## A desk phone whose project block is hidden: hiding takes the block out of the tree without
## freeing it, so the phone must not ask its device for the tree (a null tree crashed the
## release build).


func test_a_phone_out_of_the_tree_does_not_ring() -> void:
	var device := Node3D.new()
	var handset := Node3D.new()
	device.add_child(handset)
	var phone := TownPhone.new(device, handset)
	phone.ring(1.0)
	check_eq(phone.ringing, false, "not left ringing")
	check_eq(device.basis, Basis(), "not shaken")
	device.free()
