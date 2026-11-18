use std::io::{self,Read};
fn main(){
    let mut text=String::new();io::stdin().read_to_string(&mut text).unwrap();
    for result in tinkerlands_storage::replay(&text){println!("{result}");}
}
